
package main;

use strict;
use warnings;

sub HiveHome_Action_Initialize($)
{
	my ($hash) = @_;

	Log(5, "HiveHome_Action_Initialize: enter");

	# Provider

	# Consumer
	$hash->{DefFn}		= "HiveHome_Action_Define";
	$hash->{SetFn}    	= "HiveHome_Action_Set";	
	$hash->{ParseFn}	= "HiveHome_Action_Parse";
	$hash->{Match}		= "^HiveHome_Action";			# The start of the Dispatch/Parse message must contain this string to match this device.
	$hash->{AttrFn}		= "HiveHome_Action_Attr";
	$hash->{AttrList}	= "IODev " 
						. "autoAlias:1,0 "
						. $readingFnAttributes;

	Log(5, "HiveHome_Action_Initialize: exit");

	return undef;
}

sub HiveHome_Action_CheckIODev($)
{
	my $hash = shift;
	return !defined($hash->{IODev}) || ($hash->{IODev}{TYPE} ne "HiveHome_Action");
}

sub HiveHome_Action_Define($$)
{
	my ($hash, $def) = @_;

	Log(5, "HiveHome_Action_Define: enter");

	my ($name, $hiveType, $id) = split("[ \t][ \t]*", $def);
	$id = lc($id); # nomalise id

	if (exists($modules{HiveHome_Action}{defptr}{$id})) 
	{
		my $msg = "HiveHome_Action_Define: Device with id ${id} is already defined";
		Log(1, "${msg}");
		return $msg;
	}

	Log(3, "HiveHome_Action_Define id ${id}");
	$hash->{id} 	= $id;
	$hash->{type}	= $hiveType;
	$hash->{STATE} = 'Disconnected';
	
	$modules{HiveHome_Action}{defptr}{$id} = $hash;

	# Tell this Hive device to point to its parent HiveHome
	AssignIoPort($hash);

	#
	# The logic is a bit screwed up here...
	# To get the devices internals set so that the Set command works we need to ensure the following are called
	#	- HiveHome_Initialise
	#	- HiveHome_Define (physical device - doesnt set any internals)
	#	- Hive_Initialise (node)
	#	- Hive_Define
	#	-   Calls HiveHome_UpdateNodes
	#	-		Calls Dispatch for each node which calls --> Hive_Parse
	# HiveHome_UpdateNodes gets all nodes details even if they havent been defined yet, this causes autocreate requests
	# which in turn cause cannot autocreate as the device already exists.
	# So added a parameter to HiveHome_UpdateNodes which triggers whether to call Dispatch if the node exists (has been defined yet)
	#

	# Need to call HiveHome_UpdateNodes....
	if (defined($hash->{IODev}{InitNode}))
	{
		($hash->{IODev}{InitNode})->($hash->{IODev}, 1);

		if ($init_done) 
		{
			$attr{$name}{room}  = 'HiveHome';
			$attr{$name}{icon} = 'file_json-ld2';
	        $attr{$name}{devStateIcon} = 'Enabled:flux@green:activate Disabled:flux@orange:enable Disconnected:message_attention@orange .*:message_attention@red';
			$attr{$name}{autoAlias} = '1';

			HiveHome_Action_SetAlias($hash, $name);
		}
	} 
    else 
    {
		# TODO: Cant properly define the object!
	}

	Log(5, "HiveHome_Action_Define: exit");

	return undef;
}

sub HiveHome_Action_Undefine($$)
{
	my ($hash,$arg) = @_;

	Log(5, "HiveHome_Action_Undefine: enter");

	delete($modules{HiveHome_Action}{defptr}{$hash->{id}});
	
	Log(5, "HiveHome_Action_Undefine: exit");

	return undef;
}

sub HiveHome_Action_SetAlias($$)
{
	my ($hash, $name) = @_;

	Log(5, "HiveHome_Action_SetAlias: enter");

	my $attVal = AttrVal($name, 'autoAlias', undef);
	if (defined($attVal) && $attVal eq '1' && $init_done)
	{
		my $friendlyName = InternalVal($name, 'name', undef);
		if (defined($friendlyName))
		{
			my $alias = AttrVal($name, 'alias', undef);
			if (!defined($alias) || $alias ne $friendlyName)
			{
				fhem("attr ${name} alias ${friendlyName}");
			}
		}
	}	
	Log(5, "HiveHome_Action_SetAlias: exit");
	return undef;
}

sub HiveHome_Action_Attr($$$$)
{
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

	Log(5, "HiveHome_Action_Attr: enter");

	Log(4, "HiveHome_Action_Attr: Cmd: ${cmd}, Attribute: ${attrName}, value: ${attrVal}");

	if ($attrName eq 'autoAlias' && $init_done) 
	{
        if ($cmd eq 'set')
		{
			if ($attrVal eq '1')
			{
				my $alias = AttrVal($name, 'alias', undef);
				if (!defined($alias) || ($alias ne $hash->{name}))
				{
					fhem("attr ${name} alias ".$hash->{name});
				}
			}
			else
			{
				fhem("deleteattr ${name} alias");
			}
		}
		elsif ($cmd eq 'del')
		{
			# If the autoAlias attribute's previous value was 1, remove the alias.
			my $attVal = AttrVal($name, $attrName, undef);
			if (defined($attVal) && 0 != $attVal)
			{
				fhem("deleteattr ${name} alias");
			}	
		}
	}

	Log(5, "HiveHome_Action_Attr: exit");
    return undef;		
}

sub HiveHome_Action_Set($$$$)
{
	my ($hash,$name,$cmd,@args) = @_;

	Log(5, "HiveHome_Action_Set: enter - Name: ${name}, Cmd: ${cmd}");

	unshift(@args, lc($cmd));
	unshift(@args, $hash);

	my $ret = IOWrite($hash, @args);

	Log(5, "HiveHome_Action_Set: exit");

	return $ret;
}

sub HiveHome_Action_Parse($$$)
{
	my ($hash, $msg, $device) = @_;
	my ($name, $type, $id, $nodeString) = split(",", $msg, 4);

	Log(5, "HiveHome_Action_Parse: enter");

	# Convert the node details back to JSON.
	my $node = decode_json($nodeString);

	# TODO: Validate that the message is actually for a device... (is this required here? The define should have done that)
	
	if (!exists($modules{HiveHome_Action}{defptr}{$id})) 
	{
		Log(1, "HiveHome_Action_Parse: Hive $type device doesnt exist: $name");
		if (lc($node->{id}) eq lc($id)) {
			return "UNDEFINED ${name}_".${id} =~ tr/-/_/r." ${name} ${id}";
		}
		Log(1, "HiveHome_Action_Parse: Invalid parameters provided to be able to autocreate the action!");
		return "Invalid parameters provided to be able to autocreate the action!";
	}

	my $myState = "Disconnected";

	# Get the hash of the Hive device object
	my $shash = $modules{HiveHome_Action}{defptr}{$id};

	if (lc($node->{id}) eq lc($id))
	{
        $shash->{name}				= $node->{name};
        $shash->{enabled}			= $node->{enabled};

		$myState = $node->{enabled} ? "Enabled" : "Disabled";

		HiveHome_Action_SetAlias($shash, $shash->{NAME});
	}

	$shash->{STATE} = $myState;

	Log(5, "HiveHome_Action_Parse: exit");

	return $shash->{NAME};
}

1;

# Start of command ref

=pod 

=item device
=item summary HiveHome Actions
=begin html

<a name="HiveHome_Action"></a>

<h3>HiveHome Action</h3>
<ul>
	HiveHome defined Actions.<br>
	Any enabled Action created within the Hive mobile app or through the Hive webpage (<a href="https://sso.hivehome.com/?client=v3-web-prod&redirect=https://my.hivehome.com">HiveHome</a>) can have an Action device.<br>
	Action devices can be used to activate the HiveHome Actions.

	<br><br>
	<a name="HiveHome_ActionDefine"></a>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; HiveHome_Action &lt;id&gt;</code>
		<br><br>
		Define a HiveHome action.<br>
		The &lt;id&gt; is a 36 character GUID used by HiveHome to identify the action.<br>
		You should never need to specify this by yourself, the <a href="#autocreate">autocreate</a> module will automatically create all HiveHome Action devices.<br>

		Example:
		<ul>
			<code>define myHiveHome_Action HiveHome_Action 72dd3aa0-9725-44ed-9266-de25a4b253e9</code><br>
		</ul>	
	</ul>

	<br><br>
	<a name="HiveHome_ActionReadings"></a>
	<b>Readings</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHome_ActionSet"></a>
	<b>Set</b>
	<ul>
		<a name="activate"></a>
		<li><code>activate</code><br><br>
		Activates the Action.</li><br>
	</ul>

	<br><br>
	<a name="HiveHome_ActionGet"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHome_ActionAttributes"></a>
	<b>Attributes</b>
	<ul>
		<a name="autoAlias"></a>
		<li><code>autoAlias &lt;value&gt;</code> (default 1) <br><br>
		When defined, the devices alias attribute is autoamticaly set to the Actions name internal value.<br>
		This is provides a meaningful and descriptive name to be displayed on FHEMWEB compared to the devices name which is made up of the HiveHome type and it's Id.</li><br>
		<a name="IODev"></a>
		<li><code>IODev &lt;name&gt;</code><br><br>
		HiveHome device name</li><br>
	</ul>

</ul>

=end html

=cut
