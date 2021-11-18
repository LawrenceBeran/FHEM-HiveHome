
package main;

use strict;
use warnings;

sub HiveHome_Device_Initialize
{
	my ($hash) = @_;

	Log(5, "HiveHome_Device_Initialize: enter");

	# Provider

	# Consumer
	$hash->{DefFn}		= "HiveHome_Device_Define";
	$hash->{SetFn}    	= "HiveHome_Device_Set";	
	$hash->{ParseFn}	= "HiveHome_Device_Parse";
	$hash->{Match}		= "^HiveHome_Device";			# The start of the Dispatch/Parse message must contain this string to match this device.
	$hash->{AttrFn}		= "HiveHome_Device_Attr";
	$hash->{AttrList}	= "IODev " 
						. "autoAlias:1,0 "
						. $readingFnAttributes;

	Log(5, "HiveHome_Device_Initialize: exit");

	return undef;
}

sub HiveHome_Device_CheckIODev
{
	my $hash = shift;
	return !defined($hash->{IODev}) || ($hash->{IODev}{TYPE} ne "HiveHome_Device");
}

my %deviceTypeIcons = ( boilermodule => 'sani_boiler_temp', thermostatui => 'max_wandthermostat', trv => 'sani_heating', hub => 'rc_HOME' );

sub HiveHome_Device_Define
{
	my ($hash, $def) = @_;

	Log(5, "HiveHome_Device_Define: enter");

	my ($name, $hiveType, $id, $deviceType) = split("[ \t][ \t]*", $def);
	$id = lc($id); # nomalise id

	if (!defined($deviceType) or !exists($deviceTypeIcons{lc($deviceType)})) {
		my $msg = "HiveHome_Device_Define: missing or invalid device type argument missing. It must be one of; boilermodule, thermostatui, trv, hub.";
		Log(1, $msg);
		return $msg;
	}

	if (exists($modules{HiveHome_Device}{defptr}{$id})) 
	{
		my $msg = "HiveHome_Device_Define: Device with id $id is already defined";
		Log(1, "$msg");
		return $msg;
	}

	Log(4, "HiveHome_Device_Define id $id ");
	$hash->{id} 	= $id;
	$hash->{STATE} = 'Disconnected';
	$hash->{deviceType} = $deviceType;
	
	$modules{HiveHome_Device}{defptr}{$id} = $hash;

	# Tell this Hive device to point to its parent HiveHome
	AssignIoPort($hash);

	#
	# The logic is a bit screwed up here...
	# To get the devices internals set so that the Set command works we need to ensure the following are called
	#	- Hive_Hub_Initialise
	#	- Hive_Hub_Define (physical device - doesnt set any internals)
	#	- Hive_Initialise (node)
	#	- Hive_Define
	#	-   Calls Hive_Hub_UpdateNodes
	#	-		Calls Dispatch for each node which calls --> Hive_Parse
	# Hive_HubUpdateNodes gets all nodes details even if they havent been defined yet, this causes autocreate requests
	# which in turn cause cannot autocreate as the device already exists.
	# So added a parameter to Hive_Hub_UpdateNodes which triggers whether to call Dispatch if the node exists (has been defined yet)
	#

	# Need to call Hive_Hub_UpdateNodes....
	if (defined($hash->{IODev}{InitNode}))
	{
		($hash->{IODev}{InitNode})->($hash->{IODev}, 1);

		if (1 == $init_done) 
		{
			$attr{$name}{room}  = 'HiveHome';
			$attr{$name}{autoAlias} = '1';

			HiveHome_Device_SetAlias($hash, $name);

			# Show an icon representative of the devices type...
			if ($deviceTypeIcons{lc($deviceType)})
			{
	        	$attr{$name}{icon} = $deviceTypeIcons{lc($deviceType)};
			} 
			else 
			{
	        	$attr{$name}{icon} = 'unknown';
			}
#	        $attr{$name}{devStateIcon} = 'Online:10px-kreis-gruen@green Offline:10px-kreis-rot@red Disconnected:message_attention@orange Battery:batterie Signal:it_wifi';

#			$attr{$name}{stateFormat} = "online";
#			if (ReadingsVal($name, 'signal', undef))
#			{
#				$attr{$name}{stateFormat} .= "\nSignal\nsignal%";
#			}			
#			if (lc($hash->{power}) eq 'battery')
#			{
#				$attr{$name}{stateFormat} .= "\nBattery\nbattery%";
#			}
		}		
	} 
    else 
    {
		# TODO: Cant properly define the object!
	}

	Log(5, "HiveHome_Device_Define: exit");

	return undef;
}

sub HiveHome_Device_Undefine
{
	my ($hash,$arg) = @_;

	Log(5, "HiveHome_Device_Undefine: enter");

	delete($modules{HiveHome_Device}{defptr}{$hash->{id}});
	
	Log(5, "HiveHome_Device_Undefine: exit");

	return undef;
}

sub HiveHome_Device_SetAlias
{
	my ($hash, $name) = @_;

	Log(5, "HiveHome_Device_SetAlias: enter");

	my $attVal = AttrVal($name, 'autoAlias', undef);
	if (defined($attVal) && $attVal eq '1' && 1 == $init_done)
	{
		fhem("attr ${name} alias ".InternalVal($name, 'name', '').' '.InternalVal($name, 'productType', ''));
	}

	Log(5, "HiveHome_Device_SetAlias: exit");
	return undef;
}

sub HiveHome_Device_Attr
{
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

	Log(5, "HiveHome_Device_Attr: enter");

	Log(4, "HiveHome_Device_Attr: Cmd: ${cmd}, Attribute: ${attrName}, value: ${attrVal}");

	if ($attrName eq 'autoAlias' && 1 == $init_done) 
	{
        if ($cmd eq 'set')
		{
			if ($attrVal eq '1')
			{
				fhem("attr ${name} alias ".$hash->{name}.' '.$hash->{productType});
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

	Log(5, "HiveHome_Device_Attr: exit");
    return undef;		
}

sub HiveHome_Device_Set
{
	my ($hash,$name,$cmd,@args) = @_;

	Log(5, "HiveHome_Device_Set: enter - Name: ${name}, Cmd: ${cmd}");

	unshift(@args, lc($cmd));
	unshift(@args, $hash);

	my $ret = IOWrite($hash, @args);

	Log(5, "HiveHome_Device_Set: exit");

	return $ret;
}

sub HiveHome_Device_Parse
{
	my ($hash, $msg, $device) = @_;
	my ($name, $type, $id, $nodeString) = split(",", $msg, 4);

	Log(5, "HiveHome_Device_Parse: enter");

	# Convert the node details back to JSON.
	my $node = decode_json($nodeString);

	# TODO: Validate that the message is actually for a device... (is this required here? The define should have done that)
	
	if (!exists($modules{HiveHome_Device}{defptr}{$id})) 
	{
		Log(1, "HiveHome_Device_Parse: Hive $type device doesnt exist: $name");
		if (lc($node->{id}) eq lc($id)) {
			return "UNDEFINED ${name}_${type}_".${id} =~ tr/-/_/r." ${name} ${id} ".$node->{type};
		}
		Log(1, "HiveHome_Device_Parse: Invalid parameters provided to be able to autocreate the device!");
		return "Invalid parameters provided to be able to autocreate the device!";
	}

	my $myState = "Disconnected";

	# Get the hash of the Hive device object
	my $shash = $modules{HiveHome_Device}{defptr}{$id};

	if (lc($node->{id}) eq lc($id))
	{
        $shash->{deviceType}		= $node->{type};
        $shash->{name}				= $node->{name};
        $shash->{parent}			= $node->{parent};

        $shash->{manufacturer}		= $node->{internals}->{manufacturer};
        $shash->{model}		        = $node->{internals}->{model};
        $shash->{power}		        = $node->{internals}->{power};
        $shash->{version}		    = $node->{internals}->{version};

        if (defined($node->{internals}->{zone}))
        {
            $shash->{zone}		    = $node->{internals}->{zone};
        }

        if (defined($node->{internals}->{control}))
        {
            $shash->{control}		= $node->{internals}->{control};
        }

        if (defined($node->{internals}->{childLock}))
        {
            $shash->{childLock}		= $node->{internals}->{childLock};
        }

        if (defined($node->{internals}->{calibrationStatus}))
        {
            $shash->{calibrationStatus}		= $node->{internals}->{calibrationStatus};
        }

        if (defined($node->{internals}->{viewingAngle}))
        {
            $shash->{viewingAngle}		= $node->{internals}->{viewingAngle};
        }

        if (defined($node->{internals}->{mountingModeActive}))
        {
            $shash->{mountingModeActive}		= $node->{internals}->{mountingModeActive} ? "true" : "false";
        }

        if (defined($node->{internals}->{mountingMode}))
        {
            $shash->{mountingMode}		= $node->{internals}->{mountingMode};
        }


		readingsBeginUpdate($shash);

        readingsBulkUpdateIfChanged($shash, "online", $node->{readings}->{online} ? "Online" : "Offline");

		$myState = $node->{readings}->{online} ? "Connected" : "Disconnected";

        if (defined($node->{readings}->{battery})) 
        {
            readingsBulkUpdateIfChanged($shash, "battery", $node->{readings}->{battery});
			$myState .= ' (low battery)' if (int($node->{readings}->{battery}) <= 20);
        }

        if (defined($node->{readings}->{signal})) 
        {
            readingsBulkUpdateIfChanged($shash, "signal", $node->{readings}->{signal});
			$myState .= ' (poor signal)' if (int($node->{readings}->{signal}) <= 20);
        }

		readingsBulkUpdate($shash, "state", $myState);


		readingsEndUpdate($shash, 1);


		HiveHome_Device_SetAlias($shash, $name);
	}

#	$shash->{STATE} = $myState;

	Log(5, "HiveHome_Device_Parse: exit");

	return $shash->{NAME};
}

1;

# Start of command ref

=pod 
=item device
=item summary The HiveHome physical devices
=begin html

<a name="HiveHome_Device"></a>

<h3>HiveHome Device</h3>
<ul>
	The created HiveHome_Devices reference the physical elements of your HiveHome setup.
	Currently supported devices are:
	<ul>
		<li><i>Boiler module</i><br></li>
		<li><i>Thermostat UI</i><br></li>
		<li><i>Hub</i><br></li>
		<li><i>Radiator TRVs</i><br></li>
	</ul>
	The devices show the level of battery powered devices and signal strength of not wired devices.

	<br><br>
	<a name="HiveHome_DeviceDefine"></a>
	<b>Define</b>
	<ul>
        <code>define &lt;name&gt; HiveHome_device &lt;id&gt; &lt;device type&gt;</code>
        <br><br>
		The &lt;id&gt; is a 36 character GUID used by HiveHome to identify the device.<br>
		The &lt;device type&gt; can be one of; boilermodule, thermostatui, trv, hub.<br>
		You should never need to specify this yourself, the <a href="#autocreate">autocreate</a> module will automatically create all HiveHome devices.<br>
		Example:
		<ul>
			<code>define myHiveHome_Device HiveHome_Device 72dd3aa0-9725-44ed-9266-de25a4b253e9</code><br>
		</ul>	
        <br><br>
	</ul>

	<br><br>
	<a name="HiveHome_DeviceReadings"></a>
	<b>Readings</b>
	<ul>
		<a name="online"></a>
		<li><code>online</code><br><br>
		If the device is online. Possible values either Online or Offline.</li><br>
		<a name="signal"></a>
		<li><code>signal</code><br><br>
		The signal strength of the device (0 - 100).<br>
		This reading is on all deviceTypes except the hub</li><br>
		<a name="battery"></a>
		<li><code>battery</code><br><br>
		The battery level of the device (0 - 100).<br>
		This reading is only on devices where the internal 'power' value is 'battery'.</li><br>
	</ul>

	<br><br>
	<a name="HiveHome_DeviceSet"></a>
	<b>Set</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHome_DeviceGet"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHome_DeviceAttributes"></a>
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

# End of commandref 
=cut
