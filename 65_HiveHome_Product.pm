
package main;

use strict;
use warnings;
use AttrTemplate;
use SetExtensions;
use Data::Dumper;

sub trim($) { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };
sub	toString($) { my ($parameter) = @_; if (defined($parameter)) { return $parameter; } else { return '<undefined>'; } };


sub HiveHome_Product_Initialize($)
{
	my ($hash) = @_;

	Log(5, "HiveHome_Product_Initialize: enter");

	# Provider

	# Consumer
	$hash->{DefFn}		= "HiveHome_Product_Define";
	$hash->{SetFn}    	= "HiveHome_Product_Set";	
	$hash->{ParseFn}	= "HiveHome_Product_Parse";
	$hash->{AttrFn}		= "HiveHome_Product_Attr";
	$hash->{NotifyFn}	= "HiveHome_Product_Notify";

    my $templist = join(",",map { HiveHome_SerializeTemperature($_/2) }  ( HiveHome_MinTemperature()*2..HiveHome_MaxTemperature()*2 ) );
    my $tempoffsetlist = join(",",map { HiveHome_SerializeTemperature($_/2) }  ( -3*2..3*2 ) );

	$hash->{Match}		= "^HiveHome_Product";			# The start of the Dispatch/Parse message must contain this string to match this device.
	$hash->{AttrList}	= "IODev " 
						. "autoAlias:1,0 "
						. "capabilities "
						. "boostDuration:slider,15,15,420 "
						. "boostTemperature:${templist} "
						. "temperatureOffset:${tempoffsetlist} "
						. "controlZoneHeating:1,0 "
						. "controlZoneHeatingMinNumberOfTRVs "
						. $readingFnAttributes;

	Log(5, "HiveHome_Product_Initialize: exit");

	return undef;
}

sub HiveHome_Product_CheckIODev($)
{
	my $hash = shift;
	return !defined($hash->{IODev}) || ($hash->{IODev}{TYPE} ne "HiveHome_Product");
}

my %productTypeIcons = ( heating => 'sani_boiler_temp', hotwater => 'sani_water_hot', trvcontrol => 'sani_heating' );

sub HiveHome_Product_Define($$)
{
	my ($hash, $def) = @_;

	Log(5, "HiveHome_Product_Define: enter");

	my ($name, $hiveType, $id, $productType) = split("[ \t][ \t]*", $def);
	$id = lc($id); # nomalise id

	if (!defined($productType) or !exists($productTypeIcons{lc($productType)})) {
		my $msg = "HiveHome_Product_Define: missing or invalid product type argument missing. It must be one of; hotwater, heating, trvcontrol.";
		Log(1, $msg);
		return $msg;
	}
	
	if (exists($modules{HiveHome_Product}{defptr}{$id})) {
		my $msg = "HiveHome_Product_Define: Device with id $id is already defined";
		Log(1, $msg);
		return $msg;
	}

	Log(5, "HiveHome_Product_Define id $id ");
	$hash->{id} 	= $id;
	$hash->{STATE} = 'Disconnected';
	$hash->{productType} = $productType;
	
	$modules{HiveHome_Product}{defptr}{$id} = $hash;

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

		# Only interested in events from the "global" device for now.
		$hash->{NOTIFYDEV}	= "global";
		# If the product is a trv, then they are interested when the heating schedule changes.
		if (lc($productType) eq "trvcontrol")
		{
			$hash->{NOTIFYDEV}	.= ",i:TYPE=HiveHome_Product:FILTER=i:productType=heating";
		}

		if (lc($productType) eq "heating") {
			$attr{$name}{controlZoneHeating} = 1 if (!exists($attr{$name}{controlZoneHeating}));
			$attr{$name}{controlZoneHeatingMinNumberOfTRVs} = 3 if (!exists($attr{$name}{controlZoneHeatingMinNumberOfTRVs}));
		}

		$attr{$name}{autoAlias} = '1' if (!exists($attr{$name}{autoAlias}));
		$attr{$name}{room} = 'HiveHome' if (!exists($attr{$name}{room}));

		$attr{$name}{boostDuration} = 30 if (!exists($attr{$name}{boostDuration}));
		$attr{$name}{boostTemperature} = 21.0 if (!exists($attr{$name}{boostTemperature}));

		if (!exists($attr{$name}{icon}))
		{
			# Show an icon representative of the products type...
			if ($productTypeIcons{lc($productType)})
			{
				$attr{$name}{icon} = $productTypeIcons{lc($productType)};
			} 
			else 
			{
				$attr{$name}{icon} = 'unknown';
			}
		}

		if ($init_done) 
		{
			HiveHome_Product_SetAlias($hash, $name);

			# I think I can add HTML into the 'devStateIcon' attribute. Maybe I can get the boost remaining time under the 'mode' attribute icon.
			if (lc($productType) eq 'heating' or lc($productType) eq 'trvcontrol')
			{
#				$attr{$name}{devStateIcon} = 'Online:10px-kreis-gruen@green Offline:10px-kreis-rot@red Disconnected:message_attention@orange BOOST:sani_heating_boost SCHEDULE:sani_heating_automatic MANUAL:sani_heating_manual OFF:sani_heating_level_0 Temp:temp_temperature';
#				$attr{$name}{stateFormat} = "{ my \$boostVal = InternalNum(\$name, 'boost', 0, 1);my \$boostState = '';\$boostState = sprintf('%02d', \$boostVal / 60).':'.sprintf('%02d', \$boostVal % 60).\"\n\" if(\$boostVal > 0);return ReadingsVal(\$name,'mode','').\"\n\".\$boostState.\"\nTemp\n\".ReadingsVal(\$name,'temperature','').\"°C\n\".ReadingsVal(\$name,'working','') }";
				$hash->{webCmd}   = 'desiredTemperature'; # Hint for FHEMWEB
			}
			elsif (lc($productType) eq 'hotwater')
			{
#				$attr{$name}{devStateIcon} = 'Online:10px-kreis-gruen@green Offline:10px-kreis-rot@red Disconnected:message_attention@orange BOOST:sani_heating_boost SCHEDULE:sani_heating_automatic MANUAL:sani_heating_manual OFF:sani_heating_level_0';
#				$attr{$name}{stateFormat} = "{ my \$boostVal = InternalNum(\$name, 'boost', 0, 1);my \$boostState = '';\$boostState = sprintf('%02d', \$boostVal / 60).':'.sprintf('%02d', \$boostVal % 60).\"\n\" if(\$boostVal > 0);return ReadingsVal(\$name,'mode','').\"\n\".\$boostState.\"\n\".ReadingsVal(\$name,'working','') }";
			}
		}		
	} 
    else 
    {
		# TODO: Cant properly define the object!
	}

	Log(5, "HiveHome_Product_Define: exit");

	return undef;
}

sub HiveHome_Product_Undefine($$)
{
	my ($hash,$arg) = @_;

	Log(5, "HiveHome_Product_Undefine: enter");

	delete($modules{HiveHome_Product}{defptr}{$hash->{id}});
	
	Log(5, "HiveHome_Product_Undefine: exit");

	return undef;
}

sub HiveHome_Product_SetAlias($$)
{
	my ($hash, $name) = @_;

	Log(5, "HiveHome_Product_SetAlias: enter - ${name}");

	my $attVal = AttrVal($name, 'autoAlias', undef);
	if (defined($attVal) && $attVal eq '1' && $init_done)
	{
		my $friendlyName = InternalVal($name, 'name', undef);
		my $productType = InternalVal($name, 'productType', undef);
		if (defined($friendlyName) && defined($productType))
		{
			my $alias = AttrVal($name, 'alias', undef);
			if (!defined($alias) || ($alias ne "${friendlyName} ${productType}"))
			{
				fhem("attr ${name} alias ${friendlyName} ${productType}");
			}
		}
	}
	Log(5, "HiveHome_Product_SetAlias: exit");
	return undef;
}

sub HiveHome_Product_Attr($$$$)
{
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

	Log(5, "HiveHome_Product_Attr: enter");

	Log(4, "HiveHome_Product_Attr: Cmd: ${cmd}, Attribute: ${attrName}, value: ${attrVal}");

	if ($attrName eq 'autoAlias' && $init_done) 
	{
        if ($cmd eq 'set')
		{
			if ($attrVal eq '1')
			{
				my $alias = AttrVal($name, 'alias', undef);
				if (!defined($alias) || ($alias ne $hash->{name}." ".$hash->{productType}))
				{
					fhem("attr ${name} alias ".$hash->{name}." ".$hash->{productType});
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
	elsif ($attrName eq 'boostDuration')
	{
		# TODO - Verify parameter
#        if (HiveHome_IsValidNumber($attrVal))
	}
	elsif ($attrName eq 'boostTemperature')
	{
		# TODO - Verify parameter
#        if (HiveHome_IsValidTemperature($attrVal))
	}
	elsif ($attrName eq 'temperateOffset')
	{
		# TODO: Verify parameter...
		# TODO: Only valid for a heating type product.
		# TODO: Update existing settings. Can wait until the next refresh for details displayed to the screen, 
		# 		but the current temperature needs to be corrected against the offset.
	}

	Log(5, "HiveHome_Product_Attr: exit");
    return undef;		
}

sub HiveHome_Product_Set($$$$)
{
	my ($hash,$name,$cmd,@args) = @_;

	Log(5, "HiveHome_Product_Set: enter - Name: ${name}, Cmd: ${cmd}");

	my @argsCopy = @args;

	unshift(@argsCopy, lc($cmd));
	unshift(@argsCopy, $hash);

	my $ret = IOWrite($hash, @argsCopy);

	Log(5, "HiveHome_Product_Set: exit");

	if (defined($ret))
	{
		return AttrTemplate_Set($hash, $ret, $name, $cmd, @args);
	}
	return $ret;
}

sub SetInternal($$$)
{
	my ($hash, $internal, $value) = @_;

	if (defined($value))
	{
        $hash->{$internal} = $value;
	}
	else
	{
		delete($hash->{$internal}); 
	}
}

sub SetAttribute($$$)
{
	my ($hash, $attr, $value) = @_;

	if (defined($value))
	{
#		Log(3, "SetAttribute(".$hash->{NAME}." - ${attr}) - ${value}");
		fhem("attr ".$hash->{NAME}." ${attr} ${value}");
	}
	else
	{
		if (defined(AttrVal($hash->{NAME}, $attr, undef)))
		{
			fhem("deleteattr $hash->{NAME} $attr");
		}
	}
}

sub HiveHome_Product_Parse($$$)
{
	my ($hash, $msg, $device) = @_;
	my ($name, $type, $id, $nodeString) = split(",", $msg, 4);

	Log(5, "HiveHome_Product_Parse: enter");

	# Convert the node details back to JSON.
	my $node = decode_json($nodeString);

	# TODO: Validate that the message is actually for a device... (is this required here? The define should have done that)

	if (!exists($modules{HiveHome_Product}{defptr}{$id})) {
		Log(1, "HiveHome_Product_Parse: Hive $type device doesnt exist: $name");

		if (lc($node->{id}) eq lc($id)) {
			return "UNDEFINED ${name}_${type}_".${id} =~ tr/-/_/r." ${name} ${id} ".$node->{type};
		}
		Log(1, "HiveHome_Product_Parse: Invalid parameters provided to be able to autocreate the product!");
		return "Invalid parameters provided to be able to autocreate the product!";
	}

	my $myState = "Disconnected";

	# Get the hash of the Hive device object
	my $shash = $modules{HiveHome_Product}{defptr}{$id};

	if (lc($node->{id}) eq lc($id))
	{
        $shash->{productType}		= $node->{type};
        $shash->{name}				= $node->{name};
        $shash->{parent}			= $node->{parent};

		# Test to see if the product is online.... If online only some of the read values are returned.
		if (!$node->{readings}->{online})
		{
			readingsBeginUpdate($shash);
			readingsBulkUpdateIfChanged($shash, "online", $node->{readings}->{online} ? 'Online' : 'Offline');
			readingsEndUpdate($shash, 1);
		}
		else
		{
			$shash->{pmz}				= $node->{internals}->{pmz};
	        $shash->{deviceId}			= $node->{deviceId};

			if ($node->{deviceType})
			{
	        	$shash->{deviceType}		= $node->{deviceType};
			}

			# This is a hash that needs breaking down...
			my $weekProfileChanged = undef;
			my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
			foreach my $day (@daysofweek) 
			{
				# TODO: need to ensure the schedule temperatures are offset.
				if (!defined($node->{internals}->{schedule}) || !defined($node->{internals}->{schedule}->{$day}) || "" ne $node->{internals}->{schedule}->{$day})
				{
					if (lc(InternalVal($shash->{NAME}, "WeekProfile_${day}", '')) ne lc($node->{internals}->{schedule}->{$day}))
					{
						Log(4, "HiveHome_Product_Parse(".$shash->{NAME}."): WeekProfile_${day} - '".InternalVal($shash->{NAME}, "WeekProfile_${day}", '')."'");
						Log(4, "HiveHome_Product_Parse(".$shash->{NAME}."): WeekProfile_${day} - '".$node->{internals}->{schedule}->{$day}."'");
						Log(4, "HiveHome_Product_Parse(".$shash->{NAME}."): WeekProfile_${day} - modified");
						SetInternal($shash, "WeekProfile_${day}", $node->{internals}->{schedule}->{$day});
						$weekProfileChanged = 1;
					}
				}
				else
				{
					Log(2, "HiveHome_Product_Parse(".$shash->{NAME}."): WeekProfile_${day} - Empty weekday configuration!");
				}
			}

			# Optional internal values.
			SetInternal($shash, 'frostProtection',	$node->{internals}->{frostProtection});
			SetInternal($shash, 'scheduleOverride', $node->{internals}->{scheduleOverride});
			SetInternal($shash, 'zone', 			$node->{internals}->{zone});
			SetInternal($shash, 'maxEvents', 		$node->{internals}->{maxEvents});
			SetInternal($shash, 'boost', 			$node->{internals}->{boost});
			SetInternal($shash, 'previousMode', 	$node->{internals}->{previousMode});
			SetInternal($shash, 'readyBy', 			$node->{internals}->{readyBy} ? 'true' : 'false');
			SetInternal($shash, 'scheduleOverride',	$node->{internals}->{scheduleOverride} ? 'true' : 'false');
			SetInternal($shash, 'optimumStart',		$node->{internals}->{optimumStart} ? 'true' : 'false');
			SetInternal($shash, 'autoBoost',		$node->{internals}->{autoBoost});
			SetInternal($shash, 'autoBoostTarget',	$node->{internals}->{autoBoostTarget});


			SetInternal($shash, 'manufacturer',		$node->{internals}->{manufacturer});
			SetInternal($shash, 'model',			$node->{internals}->{model});
			SetInternal($shash, 'power',			$node->{internals}->{power});

			SetInternal($shash, 'childLock',		$node->{internals}->{childLock} ? 'true' : 'false');
			SetInternal($shash, 'calibrationStatus',$node->{internals}->{calibrationStatus});
			SetInternal($shash, 'viewingAngle',		$node->{internals}->{viewingAngle});
			SetInternal($shash, 'mountingModeActive',$node->{internals}->{mountingModeActive} ? "true" : "false");
			SetInternal($shash, 'mountingMode',		$node->{internals}->{mountingMode});
			SetInternal($shash, 'eui64',			$node->{internals}->{eui64});

			if (defined($node->{internals}->{holidayMode}))
			{
				SetInternal($shash, 'holidayModeEnabled',	$node->{internals}->{holidayMode}->{enabled} ? 'true' : 'false');
				SetInternal($shash, 'holidayModeActive',	$node->{internals}->{holidayMode}->{active} ? 'true' : 'false');

				if ($node->{internals}->{holidayMode}->{enabled})
				{
					# Holiday mode is enabled...
					SetInternal($shash, 'holidayModeDetails',	"Start: ".$node->{internals}->{holidayMode}->{start}." End: ".$node->{internals}->{holidayMode}->{end}." Temp: ".$node->{internals}->{holidayMode}->{temperature}."°C");
				}
				else
				{
					# Ensure Holiday details are removed from the display.
					SetInternal($shash, 'holidayModeDetails',	undef);
				}
			}

			if (defined($node->{internals}->{trvs}))
			{
	#            $shash->{trvs}		= $node->{internals}->{trvs};
	#			SetInternal($shash, 'trvs', $node->{internals}->{trvs});
	#			Log(3, "HiveHome_Product_Parse(".$shash->{NAME}."): TRVs - ".Dumper($shash->{trvs}));
			}

			SetAttribute($shash, 'capabilities',	$node->{attr}->{capabilities});

			# Offset the target temperature read from device
			my $target = $node->{readings}->{target};

			readingsBeginUpdate($shash);

			readingsBulkUpdateIfChanged($shash, "mode", $node->{readings}->{mode});
			readingsBulkUpdate($shash, "target", $target);
			readingsBulkUpdateIfChanged($shash, "working", $node->{readings}->{working} ? 'true' : 'false');
			readingsBulkUpdateIfChanged($shash, "online", $node->{readings}->{online} ? 'Online' : 'Offline');


			if (defined($node->{readings}->{firmwareVersion})) 
			{
				readingsBulkUpdateIfChanged($shash, 'firmwareVersion',	$node->{readings}->{firmwareVersion});
			}

			if (defined($node->{readings}->{temperature})) 
			{
				readingsBulkUpdate($shash, "temperature", $node->{readings}->{temperature});
			}

			if (defined($target))
			{
				$myState = $target."°C";
			}
			else 
			{
				$myState = $node->{readings}->{online} ? 'Online' : 'Offline';
			}

			if (defined($node->{internals}->{calibrationStatus}))
			{
				if (lc($node->{internals}->{calibrationStatus}) eq 'calibrating')
				{
					$myState .= ' (calibrating)';
				}
				elsif (lc($node->{internals}->{calibrationStatus}) ne 'calibrated')
				{
					$myState .= ' (requires calibrating)';
				}
			}

			if (defined($node->{readings}->{battery})) 
			{
				readingsBulkUpdate($shash, "battery", $node->{readings}->{battery});
				$myState .= ' (low battery)' if (int($node->{readings}->{battery}) <= 20);
			}

			if (defined($node->{readings}->{signal})) 
			{
				readingsBulkUpdate($shash, "signal", $node->{readings}->{signal});
				$myState .= ' (poor signal)' if (int($node->{readings}->{signal}) <= 20);
			}

#			$myState .= ' ('.lc($node->{readings}->{mode}).')';

			readingsBulkUpdate($shash, "state", $myState);

			readingsEndUpdate($shash, 1);


			if (defined($weekProfileChanged))
			{
				Log(4, "HiveHome_Product_Parse(".$shash->{NAME}."): WeekProfile has been modified");
				# Call the parent (IODev) HiveHome_TRVScheduleModified function.
				if (defined($shash->{IODev}{TRVScheduleModified}))
				{
					Log(4, "HiveHome_Product_Parse(".$shash->{NAME}."): Calling HiveHome...");
					($shash->{IODev}{TRVScheduleModified})->($shash->{IODev}, $shash);
				}
			}			
		}
		HiveHome_Product_SetAlias($shash, $shash->{NAME});
	}

	$shash->{STATE} = $myState;

	Log(5, "HiveHome_Product_Parse(".$shash->{NAME}."): exit");

	return $shash->{NAME};
}

# This function is called when events happen on other devices,
# Which devices events are handled by this function are defined in the {NOTIFYDEV} devspec
sub HiveHome_Product_Notify($$)
{
    my ($own_hash, $dev_hash) = @_;
    my $ownName = $own_hash->{NAME}; # own name / hash

    return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

    my $devName = $dev_hash->{NAME}; # Device that created the events

	return "" if ($ownName eq $devName); # Do not notify yourself

	Log(5, "HiveHome_Product_Notify(${ownName}): entry - ${devName}");

    my $events = deviceEvents($dev_hash, 1);
    return if( !$events );

	if ($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
		# This can be used to process attributes which can only be guaranteed as read after $init_done is true
		# This cannot be done in the HiveHome_Product_Defined function.

		Log(4, "HiveHome_Product_Notify(${ownName}): Set alias - ${devName}");

		HiveHome_Product_SetAlias($own_hash, $ownName);
	}
	

	if (lc($dev_hash->{TYPE}) eq "hivehome_product" && lc($own_hash->{TYPE}) eq "hivehome_product")
	{
#		my $devFriendlyName = $dev_hash->{name};
#		my $ownFriendlyName = $own_hash->{name};
#		Log(4, "HiveHome_Product_Notify(${ownFriendlyName}): - ${devFriendlyName}");

		# If the TRV is in the same zone as the heating product
		if (defined($own_hash->{zone}) && defined($dev_hash->{zone}) && lc($own_hash->{zone}) eq lc($dev_hash->{zone}))
		{
			# If a zone Heating is being boosted then all the trvs in the same zone must also be boosted.
			# When the heating reverts back to its original heating mode, the trvs must also revert back to their previous mode.
			# trvs and heating store the previous heating mode in:  props->Previous 
			if (lc($dev_hash->{productType}) eq "heating" && lc($own_hash->{productType}) eq "trvcontrol")
			{
				# What is the event?
				foreach my $event (@{$events}) 
				{
					$event = "" if(!defined($event));

					my ($name, $value) = split(": ", $event, 2);
					Log(5, "HiveHome_Product_Notify(${ownName}): Event - ${name} Value - ".toString($value));

					# Heating mode has changed
					if (lc($name) eq 'mode' && defined($value))
					{
						my $heatingOverride = AttrVal($name, 'HEATING_OVERRIDE', undef);
						if (defined($heatingOverride) && lc($heatingOverride) eq 'yes')
						{
							Log(4, "HiveHome_Product_Notify(${ownName}): HEATING_OVERRIDE attribute set, not changing its heating mode!");
						}
						else
						{
							# The heating has been boosted!
							if (lc($value) eq 'boost')
							{
								my $cmd = "set ${ownName} boost ". ReadingsVal($devName, 'target', 21).' '.InternalNum($devName, 'boost', 30);
								Log(4, "HiveHome_Product_Notify(${ownName}): ${cmd}");
								fhem($cmd);
							}
							else
							{
								# What is my current mode? If I am boost, then return to schedule
								my $myMode = lc(ReadingsVal($ownName, 'mode', ''));
								if ($myMode eq 'boost')
								{
									my $cmd = "set ${ownName} ".InternalVal($ownName, 'previousMode', 'schedule');
									Log(4, "HiveHome_Product_Notify(${ownName}): ${cmd}");
									fhem($cmd);
								}
							}
							#### TODO
							## After calling fhem we should force parse to refresh the UI with the change.
						}
					}
				}
			}
		}
	}

	Log(5, "HiveHome_Product_Notify(${ownName}): exit - ${devName}");
}

1;

=pod

=item device
=item summary HiveHome Product
=begin html

<a name="HiveHome_Product"></a>

<h3>HiveHome Product</h3>
<ul>
	The created HiveHome_Product reference the controlable elements of your HiveHome setup.
	Currently supported products are:
	<ul>
		<li><i>Heating</i><br></li>
		<li><i>Hotwater</i><br></li>
		<li><i>Radiator TRVs</i><br></li>
	</ul>

	<br><br>
	<a name="HiveHome_ProductDefine"></a>
	<b>Define</b>
	<ul>
        <code>define &lt;name&gt; HiveHome_Product &lt;id&gt; &lt;product type&gt;</code>
        <br><br>
		The &lt;id&gt; is a 36 character GUID used by HiveHome to identify the product.<br>
		The &lt;product type&gt; can be one of; heating, trvcontrol, hotwater.<br>
		You should never need to specify this by yourself, the <a href="#autocreate">autocreate</a> module will automatically create all HiveHome devices.<br>

		Example:
		<ul>
			<code>define myHiveHome_Product HiveHome_Product 72dd3aa0-9725-44ed-9266-de25a4b253e9 heating</code><br>
		</ul>	
        <br><br>
	</ul>

	<br><br>
	<a name="HiveHome_ProductReadings"></a>
	<b>Readings</b>
	<ul>
		<a name="online"></a>
		<li><code>online</code><br><br>
		If the device is online. Possible values; Online or Offline</li><br>
		<a name="working"></a>
		<li><code>working</code><br><br>
		If the device is working. Possible values; true or false</li><br>
		<a name="target"></a>
		<li><code>signal</code><br><br>
		The target temperature of the device.<br>
		This reading is on heating and trvcontrol productTypes.</li><br>
		<a name="temperature"></a>
		<li><code>temperature</code><br><br>
		The last read temperature read by the device.<br>
		This reading is on heating and trvcontrol productTypes.</li><br>
		<a name="mode"></a>
		<li><code>mode</code><br><br>
		The running mode of the device; schedule, manual, boost, off and additionaly for productType of hotwater, on.</li><br>
	</ul>

	<br><br>
	<a name="HiveHome_ProductSet"></a>
	<b>Set</b>
	<ul>
		<a name="boost"></a>
		<li><code>boost &lt;temperature&gt; &lt;time&gt;</code> (productType: heating and trvcontrol) <br>
		    <code>boost &lt;time&gt;</code> (productType - hotwater) <br><br>
		Boost the device for a period of time as defined in minutes.<br>
		temperature - 5 to 32 including half values.<br>
		E.g. 	<code>set name boost 21.5 120</code><br>
				<code>set name boost 90</code><br>
		</li><br>
		<a name="schedule"></a>
		<li><code>schedule</code><br><br>
		Set the mode of the device to run against the schedule.
		</li><br>	
		<a name="manual"></a>
		<li><code>manual &lt;temperature&gt;</code><br><br>
		Set the mode of the device to run at a set temperature until the mode is changed.<br>
		temperature - 5 to 32 including half values.<br>
		</li><br>
		<a name="off"></a>
		<li><code>off</code><br><br>
		Set the mode of the device to off.
		</li><br>	
		<a name="scheduleOverride"></a>
		<li><code>scheduleOverride &lt;temperature&gt; </code><br><br>
		Sets the device to run at a set temperature until the next scheduled time slot. At which point the device will return to run according to the set schedule.
		This will set the device into schedule mode if it is in any other mode.
		temperature - 5 to 32 including half values.
		</li><br>	
		<a name="advanceSchedule"></a>
		<li><code>advanceSchedule</code><br><br>
		Sets the mode of the device to run at the next scheduled temperature. At which point the device will return to run according to the set schedule.
		This will set the device into schedule mode if it is in any other mode.
		</li><br>	
		<a name="holidayMode"></a>
		<li><code>holidayMode &lt;start&gt; &lt;end&gt; &lt;temperature&gt;</code><br><br>
		Set the required holiday configuration.<br>
		The start and end values format is expected as follows: 'YYYY-MM-DDTHH:MM'<br>
		temperature - 5 to 32 including half values.
		E.g. <code>holidayMode 2020-12-23T00:00 2020-12-26T23:59 5.5</code>
		</li><br>	
		<a name="cancelHolidayMode"></a>
		<li><code>cancelHolidayMode</code><br><br>
		Cancels the currently configured holiday mode.
		</li><br>	
		<a name="weekProfile"></a>
		<li><code>weekProfile &lt;day&gt; &lt;target&gt;,&lt;until&gt;[,&lt;target&gt;,&lt;until&gt;][ &lt;day&gt; &lt;target&gt;,&lt;until&gt;[,&lt;target&gt;,&lt;until&gt;]]</code><br><br>
			day - mon, tue, wed, thu, fri, sat, sun<br>
			until - HH:MM. 24 hour clock starting at 00:00 to 23:59. Following untils must be later than the previous until<br>
			target - ON/OFF (productType: hotwater)  temperature value (productType: heating and trvcontrol)<br>
			temperature - 5 to 32 including half values.
		Sets the devices schedule profile.<br>
		E.g. 	<code>set name weekProfile Thu off,06:30,on,07:15,off,16:00,on,21:30,off</code><br>
				<code>set name weekProfile Thu 15.0,05:30,20.0,08:30,19.0,15:00,20.0,23:00,18.0,23:55,15.0 Fri 15.0,05:30,20.0,08:30,19.0,15:00,20.0,23:00,18.0,23:55,15.0</code><br>
		This will not modify the current profile for all unspecified days.
		</li><br>	
		<a name="childLock"></a>
		<li><code>childLock &lt;lock&gt;</code><br><br>
		Locks or unlocks the trvcontrol, locking the trv stops any tampering of the temperature setting by turning the dial.<br>
		lock - 0 or 1. 0 to unlock the trv and 1 to lock it.
		</li><br>
		<a name="calibrate"></a>
		<li><code>calibrate &lt;state&gt;</code><br><br>
		Starts or stops the trvcontrol calibration function.<br>
		state - start or stop. start to start calibrating the trv and stop to stop calibrating if calibrating is in process.
		</li><br>
		<a name="valvePosition"></a>
		<li><code>valvePosition &lt;position&gt;</code><br><br>
		Does a thing.<br>
		position - horizontal or vertical.
		</li><br>
		<a name="name"></a>
		<li><code>name &lt;name&gt;</code><br><br>
		Sets the name of the device.<br>
		name - a string value representing the new name of the device. 
		</li><br>
	</ul>
	<br><br>
	<a name="HiveHome_ProductGet"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHome_ProductAttributes"></a>
	<b>Attributes</b>
	<ul>
		<a name="autoAlias"></a>
		<li><code>autoAlias &lt;value&gt;</code> (default 1) <br><br>
		When defined, the devices alias attribute is autoamticaly set to the Actions name internal value.<br>
		This is provides a meaningful and descriptive name to be displayed on FHEMWEB compared to the devices name which is made up of the HiveHome type and it's Id.<br>
		This is automaticaly defined when the device is created.<br></li>
		<a name="capabilities"></a>
		<li><code>capabilities</code><br><br>
		List of capabilites supported by this device</li><br>
		<a name="IODev"></a>
		<li><code>IODev &lt;name&gt;</code><br><br>
		HiveHome device name</li><br>
		<a name="TemperatureOffset"></a>
		<li><code>TemperatureOffset</code><br><br>
		When defined, the offset applied to the set temperature, either manual or scheduled.<br>
		Can be any full or half number, posotive or nagative.<br>
		The temparature offset will not go outside the allowed temperature range.</li><br>
	</ul>	
</ul>


=end html

=cut
