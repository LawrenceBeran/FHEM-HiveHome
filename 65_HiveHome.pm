package main;

use strict;
use warnings;
use HiveHomeInterface;
use JSON;
use POSIX;
use Time::Local;
use Data::Dumper;
use List::Util qw(first);

# DEFINE myHiveHome HiveHome <username> <password>
my $hiveHomeClient = undef;

sub _getHiveHomeInterface($)
{
	my ($hash) = @_;

    if (!defined($hash->{HIVEHOME}{interface})) {
       	Log(3, "_getHiveHomeInterface: Creating new HiveHomeInterface object!");

        $hash->{HIVEHOME}{interface} = HiveHomeInterface->new(userName => $hash->{username}, password => $hash->{password}, 
                                            token => $hash->{HIVEHOME}{sessionToken}, refreshToken => $hash->{HIVEHOME}{refreshToken}, 
                                            accessToken => $hash->{HIVEHOME}{accessToken});
    }
    return $hash->{HIVEHOME}{interface};
}

sub HiveHome_Initialize
{
	my ($hash) = @_;

	Log(5, "HiveHome_Initialize: enter");

	# Provider
	$hash->{Clients}  = "HiveHome_.*";
	my %mc = (
		"1:HiveHome_Device" => "^HiveHome_Device",		# The start of the parent Dispatch & device Parse message must contain this string to match this device.
		"2:HiveHome_Action" => "^HiveHome_Action",		
		"3:HiveHome_Product" => "^HiveHome_Product",		
	);
	$hash->{MatchList} = \%mc;
    $hash->{WriteFn}  = "HiveHome_Write";    

	#Consumer
	$hash->{DefFn}    = "HiveHome_Define";
	$hash->{UndefFn}  = "HiveHome_Undefine";
	
    $hash->{HIVEHOME}{client} = undef;
    $hash->{helper}->{sendQueue} = [];

	Log(5, "HiveHome_Initialize: exit");
	return undef;	
}

sub HiveHome_Define($$)
{
	my ($hash, $def) = @_;

	Log(5, "HiveHome_Define: enter");

	my ($name, $type, $username, $password) = split(' ', $def);

	$hash->{STATE} = 'Disconnected';
	$hash->{INTERVAL} = 60;
	$hash->{NAME} = $name;
	$hash->{username} = $username;
	$hash->{password} = $password;

	$modules{HiveHome}{defptr} = $hash;

	# Interface used by the hubs children to communicate with the physical hub
	$hash->{InitNode} = \&HiveHome_UpdateNodes;
    # Interface used by the hubs children to say a zone has been boosted
    $hash->{ZoneBoosted} = \&HiveHome_ZoneBoosted;
    # Interface used by the hubs children to say a zone has been boosted
    $hash->{TRVScheduleModified} = \&HiveHome_TRVScheduleModified;

	# Create a timer to get object details
	InternalTimer(gettimeofday()+1, "HiveHome_GetUpdate", $hash, 0);


	
#    if ($init_done) 
    {
        $attr{$name}{room}  = 'HiveHome';
        $attr{$name}{devStateIcon} = 'Connected:10px-kreis-gruen@green Disconnected:message_attention@orange .*:message_attention@red';
        $attr{$name}{icon} = 'rc_HOME';
    }

	Log(5, "HiveHome_Define: exit");

	return undef;
}

sub HiveHome_Undefine($$)
{
	my ($hash, $def) = @_;

	Log(5, "HiveHome_Undefine: enter");

	RemoveInternalTimer($hash);

	# Close the HIVE session 
#    my $hiveHomeClient = _getHiveHomeInterface($hash);
#    if (defined($hiveHomeClient)) {
#    	$hiveHomeClient->logout();
#    }
	$hash->{HIVEHOME}{SessionId} = undef;

	Log(5, "HiveHome_Undefine: exit");

	return undef;
}

sub HiveHome_GetUpdate()
{
	my ($hash) = @_;

	Log(5, "HiveHome_GetUpdate: enter");

    HiveHome_UpdateNodes($hash, undef);
	
	InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HiveHome_GetUpdate", $hash, 0);

	Log(5, "HiveHome_GetUpdate: exit");

	return undef;
}

############################################################################
# This function boostes all TRVs that make up a zone
############################################################################

sub HiveHome_ZoneBoosted($$)
{
	my ($hash, $fromDefine) = @_;

	Log(5, "HiveHome_ZoneBoosted: enter");

	Log(5, "HiveHome_ZoneBoosted: exit");
}

sub HiveHome_TRVScheduleModified($$)
{
	my ($hash, $fromDefine) = @_;

	Log(5, "HiveHome_TRVScheduleModified: enter");
    
    Log(4, "HiveHome_TRVScheduleModified: from device: ".$fromDefine->{NAME});

    # NOTE: This function is called from HiveHome_Product_Parse which in turn is called from HiveHome_UpdateNodes using Dispatch.
    #       We just want to flag at this point that the weekProfile has been modified and then use the flag in
    #       HiveHome_UpdateNodes after all child items have been processed to determine whether the parents (zone)
    #       heating weekProfile needs to be updated.
   
    my $zone = InternalVal($fromDefine->{NAME}, 'zone', undef);
    if (defined($zone))
    {
        Log(4, "HiveHome_TRVScheduleModified: zone: ".$zone);
        $hash->{helper}{$zone} = 1;
    }

	Log(5, "HiveHome_TRVScheduleModified: exit");
}

############################################################################
# This function updates the internal and reading values on the hive objects.
############################################################################

sub HiveHome_UpdateNodes()
{
	my ($hash, $fromDefine) = @_;

	Log(5, "HiveHome_UpdateNodes: enter");

	my $presence = "ABSENT";

    my $hiveHomeClient = _getHiveHomeInterface($hash);
    if (!defined($hiveHomeClient) || !defined($hiveHomeClient->getToken()))
    {
		Log(1, "HiveHome_UpdateNodes: ".$hash->{username}." failed to logon to Hive");
		$hash->{STATE} = 'Disconnected';
    }
    else
    {
		Log(4, "HiveHome_UpdateNodes: ".$hash->{username}." succesfully connected to Hive");

		$hash->{STATE} = "Connected";

        # Only parse the details which can create the sub-components once FHEM has finished 
        # loading the config file
        if (1 == $init_done)
        {
            # Process the devices
            my @devices = $hiveHomeClient->getDevices();
            foreach my $device (@devices) 
            {
                if ($device->{type} ne 'trv')
                {
                    my $deviceString = encode_json($device);
                    Dispatch($hash, "HiveHome_Device,".$device->{type}.",".$device->{id}.",${deviceString}", undef);
                }
            }

            # Process the products
            my @products = $hiveHomeClient->getProducts();
            foreach my $product (@products)
            {
                if ($product->{type} ne 'trvcontrol')
                {
                    my $productString = encode_json($product);
                    Dispatch($hash, "HiveHome_Product,".$product->{type}.",".$product->{id}.",${productString}", undef);
                }
            }

            # Process the actions
            my @actions = $hiveHomeClient->getActions();
            foreach my $action (@actions)
            {
                my $actionString = encode_json($action);
                Dispatch($hash, "HiveHome_Action,action,".$action->{id}.",${actionString}", undef);

                # TODO: purge unspecified actions or disabled actions
            }

            ######################################################################################################
            # TODO: Work in progress... 
            #       Matching TRV devices and product info together. Create a single item for TRVs under products.
            #       Have merged info into a single hash. Need to be able to parse this to product for processing.
            my $numbZoneTRVsCallingForHeat;
            my $numbTRVsCallingForHeat;

            foreach my $product (@products)
            {
                if ($product->{type} eq 'trvcontrol')
                {
                    # Find the matching device for this product
                    my ($trvDevice) = first { 'trv' eq lc($_->{type}) && lc($_->{productId}) eq lc($product->{id}) } @devices;

                    if (defined($trvDevice))
                    {
                        # We have found a matching TRV
                        my $trv = $product;

                        $trv->{deviceType} = $trvDevice->{type};

                        while ( my ($key, $value) = each(%{$trvDevice->{internals}}) ) 
                        {
                            $trv->{internals}->{$key} = $value;
                        }

                        while ( my ($key, $value) = each(%{$trvDevice->{readings}}) ) 
                        {
                            $trv->{readings}->{$key} = $value;
                        }

                        my $productString = encode_json($trv);
                        Dispatch($hash, "HiveHome_Product,".$product->{type}.",".$product->{id}.",${productString}", undef);

                        # Initialise the TRV count for the zone if they have not already been defined.
                		$numbTRVsCallingForHeat->{$trv->{internals}->{zone}} = 0 if (!defined($numbTRVsCallingForHeat->{$trv->{internals}->{zone}}));
                		$numbZoneTRVsCallingForHeat->{$trv->{internals}->{zone}} = 0 if (!defined($numbZoneTRVsCallingForHeat->{$trv->{internals}->{zone}}));

                        # Test to see if the TRV is not at the required temperature.
                        if ($trv->{readings}->{temperature} < $trv->{readings}->{target})
                        {                           
                            $numbTRVsCallingForHeat->{$trv->{internals}->{zone}} = (!defined($numbTRVsCallingForHeat->{$trv->{internals}->{zone}})) ? 1 : $numbTRVsCallingForHeat->{$trv->{internals}->{zone}} + 1;

                            my $hashTRV = $modules{HiveHome_Product}{defptr}{$product->{id}};
                            my $controlHeating = AttrVal($hashTRV->{NAME}, 'controlZoneHeating', 0);

                            # If the TRV is configured to control the heating and it's 'calibrated'
                            # Do not let the TRV call for heat if it is calibrating.
                            if (0 != $controlHeating && uc($hashTRV->{calibrationStatus}) ne 'CALIBRATING')
                            {
                                Log(3, "HiveHome_UpdateNodes: TRV ".$trv->{name}." temperature is below its target temperature");
                                # Flag this zone as requiring heating and count the number of TRVs that are calling for heat.
                                $numbZoneTRVsCallingForHeat->{$trv->{internals}->{zone}} = (!defined($numbZoneTRVsCallingForHeat->{$trv->{internals}->{zone}})) ? 1 : $numbZoneTRVsCallingForHeat->{$trv->{internals}->{zone}} + 1;
                            }
                        }
                    }
                }
            }

            # Loop through zones
            foreach my $zone (keys %$numbZoneTRVsCallingForHeat)
            {
                Log(3, "HiveHome_UpdateNodes: Zone ".$zone." TRV(s) are ".(0 == $numbZoneTRVsCallingForHeat->{$zone} ? "not " : "")."calling for heat");

                Log(3, "HiveHome_UpdateNodes: Zone ".$zone." ".$numbTRVsCallingForHeat->{$zone}." TRV(s) are not at target and ".$numbZoneTRVsCallingForHeat->{$zone}." TRV(s) are calling for heat");


                # Get the heating product for the zone
                #   where lc(product->{productType}) == 'heating' && product->{zone} = device->{id}

                # Find the matching device for this product
                my ($heatingProduct) = first { 'heating' eq lc($_->{type}) && lc($_->{internals}->{zone}) eq lc($zone) } @products;

                if (defined($heatingProduct))
                {
                    my $hashHeating = $modules{HiveHome_Product}{defptr}{$heatingProduct->{id}};
                    my $controlHeating = AttrVal($hashHeating->{NAME}, 'controlZoneHeating', 0);
                    if (0 != $controlHeating)
                    {
                        Log(3, "HiveHome_UpdateNodes: Heating zone is ".(0 == $heatingProduct->{readings}->{working} ? "not " : "")."calling for heat. Current temp is ".$heatingProduct->{readings}->{temperature}." target temp is ".$heatingProduct->{readings}->{target});

                        my $numbTRVsRequired = AttrVal($hashHeating->{NAME}, 'controlZoneHeatingMinNumberOfTRVs', 3);

                        # If heating is not required from the zone TRVs but the heating is on...
                        if (0 == $numbZoneTRVsCallingForHeat->{$zone} && 0 != $heatingProduct->{readings}->{working})
                        {
                            # The TRVs do not require heat but the heating is on.
                            Log(3, "HiveHome_UpdateNodes: Zone '".$zone."' TRV(s) not calling for heat but zone heating is on");

                            if (lc($heatingProduct->{readings}->{mode}) eq 'schedule' && $heatingProduct->{internals}->{scheduleOverride} == 1)
                            {
                                Log(3, "HiveHome_UpdateNodes: Setting heating for zone '".$zone."' to schedule");
                                my $ret = $hiveHomeClient->_setHeatingMode($heatingProduct->{type}, $heatingProduct->{id}, 'schedule');
                            }
                            elsif (lc($heatingProduct->{readings}->{mode}) eq 'boost')
                            {
                                # TODO: Currently, if heating is set to BOOST, all TRVs are set to the same BOOST as the heating zone.
                                #       This is not the desired result as this will cause a feedback loop which will eventually adjust the entire heating to 5 degrees for the entire zone!
                                Log(3, "HiveHome_UpdateNodes: Adjusting boost for zone '".$zone."' with a temperature of ".floor($heatingProduct->{readings}->{temperature}));
#                               my $ret = $hiveHomeClient->setHeatingBoostMode($heatingProduct->{id}, floor($heatingProduct->{readings}->{temperature}, $heatingProduct->{internals}->{boost}));
                            }
                            elsif (lc($heatingProduct->{readings}->{mode}) eq 'manual')
                            {
                                Log(3, "HiveHome_UpdateNodes: Adjusting manual for zone '".$zone."' with a temperature of ".ceil($heatingProduct->{readings}->{temperature} + 1));
                                my $ret = $hiveHomeClient->setHeatingMode($heatingProduct->{id}, 'MANUAL', floor($heatingProduct->{readings}->{temperature} + 1));
                            }
                        }
                        # If TRVs are not at the required heat
                        elsif ($numbTRVsRequired <= $numbZoneTRVsCallingForHeat->{$zone} && 0 == $heatingProduct->{readings}->{working})
                        {
                            # The TRVs require heat but the zone heating os off.
                            Log(3, "HiveHome_UpdateNodes: Heating zone '".$zone."' is not on and ".$numbZoneTRVsCallingForHeat->{$zone}." TRV(s) are calling for heat, zone requires ${numbTRVsRequired} TRV(s) to switch on heating");

                            if (lc($heatingProduct->{readings}->{mode}) eq 'schedule')
                            {
                                Log(3, "HiveHome_UpdateNodes: Setting heating for zone '".$zone."' to scheduleOverride with a temperature of ".ceil($heatingProduct->{readings}->{temperature} + 1));
                                my $ret = $hiveHomeClient->_scheduleOverride($heatingProduct->{type}, $heatingProduct->{id}, ceil($heatingProduct->{readings}->{temperature} + 1));
                            }
                            elsif (lc($heatingProduct->{readings}->{mode}) eq 'boost')
                            {
                                # TODO: Currently, if heating is set to BOOST, all TRVs are set to the same BOOST as the heating zone.
                                #       This is not the desired result as this will cause a feedback loop which will eventually adjust the entire heating to 32 degrees for the entire zone!
                                Log(3, "HiveHome_UpdateNodes: Adjusting boost for zone '".$zone."' with a temperature of ".ceil($heatingProduct->{readings}->{temperature} + 1));
#                               my $ret = $hiveHomeClient->setHeatingBoostMode($heatingProduct->{id}, ceil($heatingProduct->{readings}->{temperature} + 1, $heatingProduct->{internals}->{boost}));
                            }
                            elsif (lc($heatingProduct->{readings}->{mode}) eq 'manual')
                            {
                                Log(3, "HiveHome_UpdateNodes: Adjusting manual heating for zone '".$zone."' with a temperature of ".ceil($heatingProduct->{readings}->{temperature} + 1));
                                my $ret = $hiveHomeClient->setHeatingMode($heatingProduct->{id}, 'MANUAL', ceil($heatingProduct->{readings}->{temperature} + 1));
                            }
                        }
                        elsif ($numbTRVsRequired > $numbZoneTRVsCallingForHeat->{$zone} && 0 == $heatingProduct->{readings}->{working})
                        {
                            Log(3, "HiveHome_UpdateNodes: Heating zone '".$zone."' is not on and ".$numbZoneTRVsCallingForHeat->{$zone}." TRV(s) are calling for heat, zone requires ${numbTRVsRequired} TRV(s) to switch on heating");
                        }
                    }
                }
                else
                {
                    Log(2, "HiveHome_UpdateNodes: Could not find heating product for zone ".$zone);
                }
            }

            HiveHome_SetZoneScheduleByZoneTRVSchedules($hash);

        }

        ### Get the latest used token
        my $token = $hiveHomeClient->getToken();
        $hash->{HIVEHOME}{sessionToken} = $token->{token};
        $hash->{HIVEHOME}{refreshToken} = $token->{refreshToken};
        $hash->{HIVEHOME}{accessToken} = $token->{accessToken};
    }

	Log(5, "HiveHome_UpdateNodes: exit");
}

sub _getHeatingProducts($$)
{
	my ($productType, $zone) = @_;

	my @products;

    foreach my $device ( sort keys %{$modules{HiveHome_Product}{defptr}} )
    {
        my $hash=$modules{HiveHome_Product}{defptr}{$device};
       
        next if (!defined($hash->{IODev}) || !defined($hash->{NAME}) || !defined($hash->{productType}));
        next if (lc($hash->{productType}) ne lc($productType));
        # If the zone parameter is defined, then reject all devices that are in a different zone.
        next if (defined($zone) && lc($hash->{zone}) ne lc($zone));

   		push (@products, $hash->{NAME});
    }

	return @products;        
}

sub _insertNewDayElement($$)
{
	my ($dayElements_ref, $element) = @_;

    if (!defined(@{$dayElements_ref}[-1]))
    {
        # If the array is empty, just add the passed element to the array
        push(@{$dayElements_ref}, $element);
    }
    else
    {
        # The array has some values, lets check to see if the last element has the same temperature, 
        # only add the new element if the current temp is different to the previous temp
        if ($dayElements_ref->[-1]->{temp} != $element->{temp})
        {
            push(@{$dayElements_ref}, $element);            
        }
    }
}

sub _extractHeatingElements($)
{
	my ($heatingDayShedule) = @_;
    # Remove the degrees characters from the temperatures...
    $heatingDayShedule =~ s/°C//ig;
    # Seperate each time-temp pair.
    my @heatingDayElements = split(/ \/ /, $heatingDayShedule);
    my @retDayElements;

    foreach my $heatingElement (@heatingDayElements) 
    { 
        my $hashHeatingElement = {};        
        # Seperate the time and the temp...
        $hashHeatingElement->{element} = $heatingElement;
        my ($heatingTime, $heatingTemp) = split(/-/, $heatingElement);
        # Put them into a hash and push that into a new array.
        $hashHeatingElement->{temp} = $heatingTemp;
        $hashHeatingElement->{time} = $heatingTime;
        # Seperate the time into hour and mins...
        my ($heatingHour, $heatingMin) = split(/:/, $heatingTime);
        $hashHeatingElement->{hour} = $heatingHour;
        $hashHeatingElement->{min} = $heatingMin;
        # Push the new hash into our return array.
        push(@retDayElements, $hashHeatingElement);
    }
    return @retDayElements;
}

# TODO: Need to rethink the logic here...
#
#   The heating schedule needs to cater for all TRVS. If DS TRVs are calling for more heat than US, we cannot have the US settings
#   override the DS settings.
#   Need to have some way to have the higher temp setting take precedence but still allow for the temp to go down if both require
#   the temp to drop.
#       TRV01:              00:00-18 / 06:15-21 /               07:30-17 /                          15:00-20 /              18:00-21 /  23:00-17
#       TRV02:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV03:              00:00-15 / 06:15-20 /                                       08:30-15 /              17:00-20 /              23:00-15 / 23:55-15
#       TRV04:              00:00-19 / 06:15-22 /               07:30-18 /                          15:00-21 /              18:00-22 /  23:00-18
#       TRV05:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV06:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV07:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV08:              00:00-18 / 06:15-21 /               07:30-17 /                          15:00-20 /              18:00-21 /  23:00-17
#       TRV09:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV10:              00:00-15 / 06:15-20 /                                       08:30-15 /              17:00-20 /              23:00-15 / 23:55-15
#       TRV11:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV12:              00:00-18 / 06:15-21 /               07:30-17 /                          15:00-20 /              18:00-21 /  23:00-17
#       TRV13:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15
#       TRV14:              00:00-15 /              06:30-21 /              08:00-20 /                                      18:00-21 /  23:00-15

#       NEW:                00:00-19 / 06:15-22 /   06:30-21 /  07:30-18 /  08:00-20 /  08:30-15 /  15:00-21 /  17:00-20 /  18:00-22 /  23:00-18 / 23:55-15
#
#       REQUIRED:           00:00-19 / 06:15-22 / 08:00-20 / 15:00-21 / 18:00-22 / 23:00-18

#   Need to think about the ranges, not about set points. E.g. TRV05 sets the temp to 20 at 08:00, any temperature below this until its next setpoint at 18:00 should be ignored.

sub _mergeDayHeatingShedule($$$$)
{
	my ($hiveHomeClient, $day, $heatingDayShedule, $trvDayShedule) = @_;
    my $retDaySchedule = undef;

    if (defined($trvDayShedule))
    {
        Log(4, "_mergeDayHeatingShedule(${day}) - trv:     ${trvDayShedule}");

        # If we have a heating schedule defined for the day
        if (defined($heatingDayShedule))
        {
            # And a string compare does not match
            if ($heatingDayShedule ne $trvDayShedule)
            {
                Log(4, "_mergeDayHeatingShedule(${day}) - heating: ${heatingDayShedule}");

                # Breakdown both schedules into their time/temp sections.
                # UI schedule looks like - 00:00-15°C / 06:15-20°C / 08:30-15°C / 15:00-20°C / 23:00-15°C / 23:55-15°C
                # could also have temp with decimals.

                # Convert the heating day schedule to an array of hashes(temp and time).
                my @heatingDayElements = _extractHeatingElements($heatingDayShedule);
                my @trvDayElements = _extractHeatingElements($trvDayShedule);

                # Get the first heating and trv elements. These will both be for time 00:00
                my $trvElement = shift(@trvDayElements);
                my $heatingElement1 = shift(@heatingDayElements);
                # Get the next heating elements.
                my $heatingElement2 = shift(@heatingDayElements);

                my @retDayElements;

                # Loop through the heating elements array (removing the first element each time).
                my $finished = 0;
                while ($finished == 0)
                {
                    if (defined($heatingElement1) && defined($trvElement))
                    {
                        # If both elements are the same.
                        if ($heatingElement1->{element} eq $trvElement->{element})
                        {
                            # Get next TRV day element.
                            $trvElement = shift(@trvDayElements);
                        }
                        elsif ($heatingElement1->{time} eq $trvElement->{time})
                        {
                            # The times are the same, so we need to use the hotter temperature.
                            if ($trvElement->{temp} > $heatingElement1->{temp})
                            {
                                $heatingElement1->{temp} = $trvElement->{temp};
                                $heatingElement1->{element} = $heatingElement1->{time}."-".$heatingElement1->{temp};
                            }
                            # Get next TRV day element.
                            $trvElement = shift(@trvDayElements);
                        }
                        else
                        {
                            # At this point the TRV element will always be after the first heating element.

                            # If there is another heating element
                            if (defined($heatingElement2))
                            {
                                # Is the TRV day element before the 2nd heating day element. I.e. its between our two heating elements.
                                if ($heatingElement2->{hour} > $trvElement->{hour} || ($heatingElement2->{hour} == $trvElement->{hour} && $heatingElement2->{min} > $trvElement->{min}))
                                {
                                    # If the TRV element temp is greater than the first heating element temp.
                                    if ($trvElement->{temp} > $heatingElement1->{temp})
                                    {
                                        # Push the TRV day element into the ret array.
                                        _insertNewDayElement(\@retDayElements, $trvElement);
                                        # Set heating element 1 to be the TRV day element.
                                        $heatingElement1 = $trvElement;
                                        # Get the next TRV day element.
                                        $trvElement = shift(@trvDayElements);
                                    }
                                    else
                                    {
                                        # The TRV element temp is less than the heating element temp. We can drop this TRV day element.
                                        # Get the next TRV day element.
                                        $trvElement = shift(@trvDayElements);
                                    }
                                }
                                else
                                {
                                    # The TRV day element is after the 2nd heating element.

                                    # Push the 1st heating day element into the ret array.
                                    _insertNewDayElement(\@retDayElements, $heatingElement1);
                                    # Shift the heating2 day elements over into position one and get a new heating day element.
                                    $heatingElement1 = $heatingElement2;
                                    $heatingElement2 = shift(@heatingDayElements);
                                }
                            }
                            else
                            {
                                # If there are no more heating elements...
                                # Push the heating day element into the new array
                                _insertNewDayElement(\@retDayElements, $heatingElement1);
                                # Push the TRV day element into the new array.
                                _insertNewDayElement(\@retDayElements, $trvElement);
                                # Get the next TRV day element.
                                $trvElement = shift(@trvDayElements);
                                # Reset the heating day element to flag that there are no longer any heating elements.
                                $heatingElement1 = undef;
                            }
                        }
                    }
                    elsif (defined($trvElement))
                    {
                        # Push TRV element into the return array.
                        _insertNewDayElement(\@retDayElements, $trvElement);
                        # Get new element from heating array.
                        $trvElement = shift(@trvDayElements);
                    }
                    elsif (defined($heatingElement1))
                    {
                        # Push heating element into the return array.
                        _insertNewDayElement(\@retDayElements, $heatingElement1);
                        # Shift the heating2 day elements over into position one and get a new heating day element.
                        $heatingElement1 = $heatingElement2;
                        $heatingElement2 = shift(@heatingDayElements);
                    }
                    else
                    {
                        # No more elements in either array. Time to finish!
                        $finished = 1;                        
                    }
                }

                # Check if the new day schedule has the allowed number of elements!
                if ($hiveHomeClient->_getMaxNumbHeatingElements() >= $#retDayElements)
                {
                    # The number of day elements are within the allowed range!
                    $retDaySchedule =  join(" / ", map($_->{element},  @retDayElements));
                }
                else
                {
                    # TODO: There are too many elements in the day.
                    #       Loop through the elements and merge some of them together
                    #   
                    #       Find the two closest elements in time/temp and remove one element and set the temp to the maximum so it covers all TRVS.
                    #       E.g.    06:30-20 / 07:00-21 / 12:00-19
                    #       The 6:30 element would need to be changed to 21 and the 07:00 removed.
                    #               06:30-21 / 12:00-19
                    #
                    # The number of day elements are within the allowed range!

                    $retDaySchedule =  join(" / ", map($_->{element},  @retDayElements));
                    Log(1, "_mergeDayHeatingShedule(${day}) - Too many elements - ${retDaySchedule}");
                }
            }
            else
            {
                # The current heating schedule is good
                $retDaySchedule = $heatingDayShedule;
            }
        }
        # No current heating schedule is defined yet for the day
        else
        {
            # Initialise it...
            $retDaySchedule = $trvDayShedule;
        }
    }
    else
    {
        # No TRV schedule defined, return the current heating schedule for the day.
        $retDaySchedule = $heatingDayShedule;
    }
    Log(4, "_mergeDayHeatingShedule(${day}) - output:  ${retDaySchedule}");

    return $retDaySchedule;
}

sub HiveHome_SetZoneScheduleByZoneTRVSchedules($)
{
	my ($hashHiveHome) = @_;

	Log(5, "HiveHome_SetZoneScheduleByZoneTRVSchedules: enter");

    my $hiveHomeClient = _getHiveHomeInterface($hashHiveHome);
    # TODO: exit if undefined.

    # For each heating products
    my @heatingProducts = _getHeatingProducts('heating', undef);
	foreach my $heatingProduct (@heatingProducts) 
	{
        # Get the heating products zone.
		my $heatingZone = lc(InternalVal($heatingProduct, "zone", undef));
        if (defined($heatingZone))
        {
            Log(4, "HiveHome_SetZoneScheduleByZoneTRVSchedules: Checking zone TRV has been updated: ${heatingProduct}");

            # Test to see if a TRV within that heating zone has been modified 
            if (defined($hashHiveHome->{helper}{$heatingZone}))
            {
                Log(1, "HiveHome_SetZoneScheduleByZoneTRVSchedules: Zone TRV has been updated: ${heatingProduct}");

                delete($hashHiveHome->{helper}{$heatingZone});

                # Test to see if the heating product that controls that zone is configured to have its schedule set by its TRVs
#                my $setZoneScheduleByTRVSchedule = AttrVal($heatingProduct, 'setZoneScheduleByTRVSchedule', 0);
#                if (0 != $setZoneScheduleByTRVSchedule)
                {
                    Log(1, "HiveHome_SetZoneScheduleByZoneTRVSchedules: Zone is configured to be set by zone TRVs: ${heatingProduct}");

                    my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
                    my %heatingSchedule;

                    # Get all TRVs in the heating zone.
                    my @zoneTRVs = _getHeatingProducts('trvcontrol', $heatingZone);
                    foreach my $zoneTRV (@zoneTRVs)
                    {
                        Log(4, "HiveHome_SetZoneScheduleByZoneTRVSchedules: TRV is part of zone: ${zoneTRV}");

                        foreach my $day (@daysofweek) 
                        {
                            $heatingSchedule{${day}} = _mergeDayHeatingShedule($hiveHomeClient, $day, $heatingSchedule{${day}}, InternalVal($zoneTRV, "WeekProfile_$day", undef));
                        }
                    }

                    # TODO: Compare generated schedule with current schedule...

                    # TODO: If schedules do not match, then apply new schedule to heating.

                }
            }
        }
    }

	Log(5, "HiveHome_SetZoneScheduleByZoneTRVSchedules: exit");
}

sub HiveHome_Write_Action($$$$@)
{
    my ($hash, $hiveHomeClient, $shash, $cmd, @args) = @_;

    Log(5, "HiveHome_Write_Action: enter");

    my $ret = undef;

    if (lc($cmd) eq lc('activate'))
    {
        $ret = $hiveHomeClient->activateAction($shash->{id});
    }
#    elsif (lc($cmd) eq lc('enable'))
#    {
#        $ret = $hiveHomeClient->enableAction($shash->{id}, @args[0]);
#    }
	else
	{
		$ret = "unknown argument ${cmd} choose one of activate:noArg";
	}

    Log(5, "HiveHome_Write_Action: exit");

    return $ret;
}

sub HiveHome_Write_Device($$$$@)
{
    my ($hash, $hiveHomeClient, $shash, $cmd, @args) = @_;

    Log(5, "HiveHome_Write_Device: enter");

    my $ret = undef;

    if (lc($cmd) eq lc('name'))
    {
        if ($args[0])
        {
            ## TODO: Not sure the boilermodule deviceType has a name or can have its name changed
            $ret = $hiveHomeClient->_setDeviceName($shash->{deviceType}, $shash->{id}, $args[0]);
        }
        else
        {
            $ret = "Missing argument!";
        }
    }
	else
	{
		$ret = "unknown argument ${cmd} choose one of name ";
	}

    Log(5, "HiveHome_Write_Device: exit");

    return $ret;
}

sub HiveHome_IsValidTemperature($)
{
    # TODO: There is a PERL warning thrown from this function.
    #       Use of uninitialized value $val in pattern match
    my ($val) = @_;
    return $val =~ /^[1-9][0-9](\.[05])?$/;
}

sub HiveHome_IsValidNumber
{
    my ($val) = @_;
    return $val =~ /^[1-9][0-9]*$/;
}

sub HiveHome_IsValidTime 
{ 
    my $s = shift; 
    if ($s =~ s/^([0-9]|0[0-9]|1[0-9]|2[0-3]):([0-5][0-9])$/sprintf('%02d:%02d',$1,$2)/e) 
    { 
        return $s; 
    } 
    else 
    { 
        return undef; 
    } 
} 

sub HiveHome_IsValidHotWaterTemp 
{ 
    my $s = shift; 
    if ($s =~ s/^(ON|OFF|HEAT)$/\U$1/i) 
    { 
        return $s; 
    } 
    else 
    { 
        return undef; 
    } 
}

sub HiveHome_ParseWeekCmdString($$)
{
    my $weekString = shift;
    my $tempOffset = shift;

    Log(5, "HiveHome_ParseWeekCmdString: Enter - WeekProfile - ".$weekString);

    # Split the week string into its component (day) parts 
    my @array = split(/(monday|mon|tuesday|tue|wednesday|wed|thursday|thu|friday|fri|saturday|sat|sunday|sun)/i, HiveHomeInterface::_trim($weekString));
    my %dayHash = (mon => "monday", tue => "tuesday", wed => "wednesday", thu => "thursday", fri => "friday", sat => "saturday", sun => "sunday");

    # Remove the first element, which is blank
    shift(@array);

    my $valid_string = 1;
    my $weekHash = {};

    for (my $day = 0;$day <= $#array && $valid_string;$day += 2)
    {
        if (!exists($dayHash{lc($array[$day])}))
        {
            Log(2, "HiveHome_ParseWeekCmdString: Invalid day element".$array[$day]);
            $valid_string = undef;
        }
        else
        {
            # Substitute HEAT with ON.
            $array[$day+1] =~ s/HEAT/ON/ig;

            if (defined($tempOffset) && $tempOffset != 0)
            {
                Log(3, "HiveHome_ParseWeekCmdString: Offset days temperature original values - ".$array[$day+1]);

                # Seperate the time and values from the cmd string.
                my (@value, @time);
                my $i;
                push @{ $i++ % 2 ? \@time : \@value }, $_ for split(/,/, HiveHomeInterface::_trim($array[$day+1]));

                # Put them back together again, but with the temperature values offset.
                $array[$day+1] = "";
                for my $i ( 0 .. ($#value - 1))
                {
                    $array[$day+1] .= HiveHome_AddOffestTemperature($value[$i], $tempOffset).",".$time[$i].",";
                }
                $array[$day+1] .= HiveHome_AddOffestTemperature($value[$#value], $tempOffset);

                Log(3, "HiveHome_ParseWeekCmdString: Offset days temperature offset values - ".$array[$day+1]);
            }

            $weekHash->{$dayHash{lc($array[$day])}} = HiveHomeInterface::_trim($array[$day+1]);
        }
    }

    if (!defined($valid_string))
    {
        $weekHash = undef;
    }

    Log(5, "HiveHome_ParseWeekCmdString: Exit");

    return $weekHash;
}

sub HiveHome_ConvertUIDayProfileStringToCmdString($)
{
    my $dayString = shift;

    Log(5, "HiveHome_ConvertUIDayProfileStringToCmdString: Enter - dayString - ".$dayString);

    my $retCmdString = undef;

    # Remove the degrees characters from the temp...
    $dayString =~ s/°C//ig;

    # Parse the UI string from format: 
    #       00:00-OFF / 06:30-ON / 07:15-OFF / 16:00-ON / 21:30-OFF
    # into 
    #       off,06:30,on,07:15,off,16:00,on,21:30,off

    my @dayElements = split(/ \/ /, $dayString);
    my $firstElement = 1;

    foreach my $element (@dayElements)
    {
        # Seperate the time and the temp...
        my ($time, $temp) = split(/-/, $element);

        if (defined($firstElement))
        {
            $retCmdString = $temp;
            $firstElement = undef;
        }
        else
        {
            $retCmdString .= ','.$time.','.$temp;
        }
    }

    Log(5, "HiveHome_ConvertUIDayProfileStringToCmdString: Exit - retString - ".$retCmdString);

    return $retCmdString;
}

sub HiveHome_AddOffestTemperature($$)
{
    my $temp = shift;
    my $tempOffset = shift;

    Log(5, "HiveHome_AddOffestTemperature: Enter - Temp - ${temp} tempOffset - ${tempOffset}");

    if (defined($tempOffset) && HiveHome_IsValidTemperature($temp))
    {
        $temp = HiveHome_MakeValidTemperature($temp + $tempOffset);
    }

    Log(5, "HiveHome_AddOffestTemperature: Exit - return - ${temp}");

    return $temp;
}

sub HiveHome_SubOffestTemperature($$)
{
    my $temp = shift;
    my $tempOffset = shift;

    Log(5, "HiveHome_SubOffestTemperature: Enter - Temp - ${temp} tempOffset - ${tempOffset}");

    if (defined($tempOffset) && HiveHome_IsValidTemperature($temp))
    {
        $temp = HiveHome_MakeValidTemperature($temp - $tempOffset);
    }

    Log(5, "HiveHome_SubOffestTemperature: Exit - return - ${temp}");

    return $temp;
}

sub HiveHome_MakeValidTemperature($)
{
    my $temp = shift;

    Log(5, "HiveHome_MakeValidTemperature: Enter - Temp - ${temp}");

    if ($temp > HiveHome_MaxTemperature())
    {
        $temp = HiveHome_MaxTemperature();
    }
    elsif ($temp < HiveHome_MinTemperature())
    {
        $temp = HiveHome_MinTemperature();
    }
    Log(5, "HiveHome_MakeValidTemperature: Exit - Temp - ${temp}");
    return $temp;
}

sub HiveHome_MinTemperature()
{
    return 5;
}

sub HiveHome_MaxTemperature()
{
    return 32;
}

sub HiveHome_SerializeTemperature 
{
    # Print number in format "0.0", pass "on" and "off" verbatim, convert 30.5 and 4.5 to "on" and "off"
    # Used for "desiredTemperature", "ecoTemperature" etc. but not "temperature"

    my $t = shift;
#    return $t    if ( ($t eq 'on') || ($t eq 'off') );
#    return 'off' if ( $t ==  4.5 );
#    return 'on'  if ( $t == 30.5 );
    return sprintf('%2.1f', $t);
}

sub HiveHome_Write_Product($$$$@)
{
    my ($hash, $hiveHomeClient, $shash, $cmd, @args) = @_;

    Log(5, "HiveHome_Write_Product: enter");

    my $ret = undef;

	# The commands are dependant on the product type (I think).
	#	

	# For product types of: heating, hotwater, trvcontrol
	$cmd = (lc($cmd) eq 'auto') ? 'schedule' : lc($cmd);
	
    if (!defined($shash->{productType}))
    {
        Log(1, "HiveHome_Write_Product - productType not defined for ".$shash->{NAME});
    }
    else
    {
        Log(4, "HiveHome_Write_Product(${cmd}): product type: ".$shash->{productType});

        if ($cmd eq 'weekprofile')
        {
            my $weekString = join(" ", @args);
            # Remove redundant '.0' elements from temperatures.
            $weekString =~ s/[.]0//ig;

            Log(4, "HiveHome_Write_Product(${cmd}): WeekProfile - ".$weekString);

            # Get the components heating offset.
            my $tempOffset = AttrVal($shash->{NAME}, 'temperatureOffset', 0);

            my $weekProfile = HiveHome_ParseWeekCmdString($weekString, $tempOffset);
            if (!defined($weekProfile))
            {
                $ret = "invalid weekprofile value - ".$weekProfile;
                Log(1, "HiveHome_Write_Product(${cmd}): Invalid command argument - ".$weekString);
            }
            else
            {
                my $weekProfileCmdString = undef;
                my $different = undef;
                my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
                foreach my $day (@daysofweek) 
                {
                    if (!defined($weekProfile->{$day}))
                    {
                        $weekProfile->{$day} = HiveHome_ConvertUIDayProfileStringToCmdString($shash->{"WeekProfile_".$day});
                    }
                    else
                    {
                        my $dayProfile = HiveHome_ConvertUIDayProfileStringToCmdString($shash->{"WeekProfile_".$day});
                        $dayProfile =~ s/[.]0//ig;

                        if (lc($dayProfile) eq lc($weekProfile->{$day})) {
                            Log(1, "HiveHome_Write_Product(${cmd}): Provided profile (".$weekProfile->{$day}.") matches current - ".$dayProfile);
                        }
                        else {
                            Log(1, "HiveHome_Write_Product(${cmd}): Provided profile (".$weekProfile->{$day}.") different to current- ".$dayProfile);
                            $different = 1;
                        }
                    }
                    $weekProfileCmdString .= $day.' '.$weekProfile->{$day}.' ';
                }

                if (defined($different)) {
                    Log(4, "HiveHome_Write_Product(${cmd}): Complete WeekProfile - ".$weekProfileCmdString);
                    my $resp = $hiveHomeClient->_setSchedule(lc($shash->{productType}), $shash->{id}, $weekProfileCmdString);
                } else {
                    Log(4, "HiveHome_Write_Product(${cmd}): WeekProfile not changed from current - ".$weekProfileCmdString);
                }
            }
        }
        elsif ((lc($shash->{productType}) eq 'heating') and ($cmd eq 'holidaymode'))
        {
            # Three params
            #   args[0] = start date/time
            #   args[1] = end date/time
            #   args[2] = temp
            # Date/times in the format of YYYY-MM-DDTHH:MM

            if ($args[0] and $args[1] and $args[2])
            {
                Log(4, "HiveHome_Write_Product(${cmd})");
                $ret = $hiveHomeClient->setHolidayMode($args[0], $args[1], $args[2]);
            }
            else
            {
                Log(4, "HiveHome_Write_Product(${cmd}): Not enough parameters, expecting three!");
                $ret = "holidaymode requires three parameters; start datetime, end datetime and temperature";
            }
        }
        elsif ((lc($shash->{productType}) eq 'heating') and ($cmd eq 'cancelholidaymode'))
        {
            Log(4, "HiveHome_Write_Product(${cmd})");
            $ret = $hiveHomeClient->cancelHolidayMode();
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'name'))
        {
            Log(3, "HiveHome_Write_Product(${cmd}) - ${args[0]}");

            if ($args[0])
            {
                $ret = $hiveHomeClient->_setDeviceName($shash->{deviceType}, $shash->{deviceId}, $args[0]);
            }
            else
            {
                $ret = "invalid value '${args[0]}', must contain a name";
            }
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'calibrate'))
        {
            if ($args[0])
            {
                if (lc($args[0]) eq 'start')
                {
                    $ret = $hiveHomeClient->trvCalibrate($shash->{deviceId}, 1);
                }
                elsif (lc($args[0]) eq 'stop')
                {
                    $ret = $hiveHomeClient->trvCalibrate($shash->{deviceId}, undef);
                }
                else
                {
                    $ret = "invalid value '${args[0]}', must be either start or stop";
                }
            }
            else
            {
                $ret = "missing argument value, must be either start or stop";
            }
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'valveposition'))
        {
            Log(3, "HiveHome_Write_Product(${cmd}) - ${args[0]}");

            if ($args[0])
            {
                $ret = $hiveHomeClient->setTRVViewingAngle($shash->{deviceId}, $args[0]);
            }
            else
            {
                $ret = "missing argument value, must be either horizontal or vertical";
            }
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'childlock'))
        {
            Log(3, "HiveHome_Write_Product(${cmd}) - ${args[0]}");

            if (defined($args[0]) && ($args[0] == 0 || $args[0] == 1))
            {
                $ret = $hiveHomeClient->setTRVChildLock($shash->{deviceId}, $args[0]);
            }
            else
            {
                $ret = "missing argument value, must be either 0 or 1";
            }
        }        
        elsif ((lc($shash->{productType}) eq 'heating') or (lc($shash->{productType}) eq 'trvcontrol'))
        {
            if ($cmd eq 'desiredtemperature')
            {
                # If the command is 'desiredTemperature' then the first argument can be translated into the command or a temperature for manual.
                if (HiveHome_IsValidTemperature($cmd))
                {
                    $args[0] = $cmd;
                    $cmd = 'manual';
                }
                else
                {
                    $cmd = $args[0];
                }
            }

            # Can have arguments of:
            #	SCHEDULE, MANUAL, OFF, BOOST
            if (($cmd eq 'schedule') or ($cmd eq 'off'))
            {
                $ret = $hiveHomeClient->_setHeatingMode($shash->{productType}, $shash->{id}, $cmd);
            }
            elsif ($cmd eq 'boost') 
            {
                # BOOST can be provided with or without parameters
                #       If no parameters then it will use the internals boostTemperature and boostDuration
                if (!defined($args[0]) || $args[0] eq '')
                {
                    # No parameters provided, use the internals.
                    my $temp = AttrVal($shash->{NAME}, 'boostTemperature', 20);
                    $ret = $hiveHomeClient->_setHeatingBoostMode($shash->{productType}, $shash->{id}, $temp, AttrVal($shash->{NAME}, 'boostDuration', 30));
                }
                elsif (!HiveHome_IsValidTemperature($args[0]))
                {
                    $ret = "invalid value '${args[0]}', must be a temperature value";
                }
                elsif (!HiveHome_IsValidNumber($args[1]))
                {
                    $ret = "invalid value '${args[1]}', must be a time in mins";
                }
                else
                {
                    my $temp = $args[0];
                    $ret = $hiveHomeClient->_setHeatingBoostMode($shash->{productType}, $shash->{id}, $temp, $args[1]);
                }
            }
    #        elsif (($cmd eq 'manual') or ($cmd eq 'frostprotection'))
            elsif (($cmd eq 'manual') or ($cmd eq 'scheduleoverride'))
            {
                # MANUAL and SCHEDULEOVERRIDE next arg is temperature.
                # 		Can we get devices minimum and maximum temperature from device details
                #		and only allow whole or half decimal places			

                if (HiveHome_IsValidTemperature($args[0]))
                {
                    if ($cmd eq 'manual')
                    {
                        $ret = $hiveHomeClient->_setHeatingMode($shash->{productType}, $shash->{id}, $cmd, $args[0]);
                    }
                    elsif ($cmd eq 'scheduleoverride')
                    {
                        $args[0] = HiveHome_AddOffestTemperature($args[0], AttrVal($shash->{NAME}, 'temperatureOffset', 0));

                        # Ensure the device is in schedule mode otherwise schedule override will have no affect 
                        $ret = $hiveHomeClient->_setHeatingMode($shash->{productType}, $shash->{id}, 'schedule');
                        $ret = $hiveHomeClient->_scheduleOverride($shash->{productType}, $shash->{id}, $args[0]);
                    }
                    elsif ($cmd eq 'frostprotection')
                    {
                        $ret = $hiveHomeClient->setFrostProtection($shash->{productType}, $shash->{id}, $args[0]);
                    }
                }
                else
                {
                    $ret = "invalid value '${args[0]}', must be a temperature value";
                }
            }
            elsif ($cmd eq 'advanceschedule')
            {
                # Ensure the device is in schedule mode otherwise schedule override will have no affect 
                $ret = $hiveHomeClient->_setHeatingMode($shash->{productType}, $shash->{id}, 'schedule');

                $ret = $hiveHomeClient->_advanceSchedule($shash->{productType}, $shash->{id});
            }
            elsif (lc($shash->{productType}) eq 'heating')
            {
                my $templist = join(",",map { HiveHome_SerializeTemperature($_/2) }  ( HiveHome_MinTemperature()*2..HiveHome_MaxTemperature()*2 ) );
                my $desOptions = "off,schedule,advanceSchedule,boost,${templist}";

                $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg manual:${templist} boost weekprofile holidaymode cancelholidaymode:noArg advanceSchedule:noArg scheduleOverride:${templist} desiredTemperature:${desOptions} ";
    #            $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg manual:knob,min:5,max:32,step:0.5,linecap:round,fgColor:red boost weekprofile frostprotection:knob,min:5,max:32,step:0.5,linecap:round,fgColor:red holidaymode";
            }
            else
            {
                my $templist = join(",",map { HiveHome_SerializeTemperature($_/2) }  ( HiveHome_MinTemperature()*2..HiveHome_MaxTemperature()*2 ) );
                my $desOptions = "off,schedule,advanceSchedule,boost,${templist}";

                $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg manual:${templist} boost weekprofile advanceSchedule:noArg scheduleOverride:${templist} desiredTemperature:${desOptions} name calibrate:start,stop valveposition:horizontal,vertical childLock:0,1 ";
            }
        }
        elsif (lc($shash->{productType}) eq 'hotwater')
        {
            # Can have arguments of:
            #	SCHEDULE, ON, OFF, BOOST

            if (($cmd eq 'schedule') or ($cmd eq 'off') or ($cmd eq 'on'))
            {
                # No additional args are required.
                $ret = $hiveHomeClient->setHotWaterMode($shash->{id}, $cmd);
            }
            elsif ($cmd eq 'boost')
            {
                # Verify duration is a number...
                if (HiveHome_IsValidNumber($args[0]))
                {
                    $ret = $hiveHomeClient->setHotWaterBoostMode($shash->{id}, $args[0]);
                }
                else
                {
                    $ret = "invalid value '${args[0]}', must be a time in mins";
                }
            }
            else
            {
                $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg on:noArg boost:slider,15,15,420 weekprofile";
            }
        }
        else
        {
            Log(2, "HiveHome_Write_Product(${cmd}): Unkown product type: ".$shash->{productType});
            $ret = "unknown productType ".$shash->{productType}; 
        }
    }
#   	readingsBulkUpdate($shash, "lastCmd", 'mode '.$node->{readings}->{mode});


    Log(5, "HiveHome_Write_Product(${cmd}): exit");
    return $ret;
}

sub _verifyWriteActionCommandArgs($$$$)
{
    my ($hash, $shash, $cmd, @args) = @_;

    Log(5, "_verifyWriteActionCommandArgs: enter");

    my $ret = undef;

    if (lc($cmd) ne lc('activate'))
	{
		$ret = "unknown argument ${cmd} choose one of activate:noArg";
	}

    Log(5, "_verifyWriteActionCommandArgs: exit");

    return $ret;
}

sub _verifyWriteProductCommandArgs($$$$)
{
    my ($hash, $shash, $cmd, @args) = @_;

    Log(5, "_verifyWriteProductCommandArgs: enter");

    my $ret = undef;


	# For product types of: heating, hotwater, trvcontrol
	$cmd = (lc($cmd) eq 'auto') ? 'schedule' : lc($cmd);
	
    if (!defined($shash->{productType})) 
    {
        Log(1, "_verifyWriteProductCommandArgs - productType not defined for ".$shash->{NAME});
    } 
    else 
    {
        if ($cmd eq 'weekprofile')
        {
            my $weekString = join(" ", @args);

            # Get the components heating offset.
            my $tempOffset = AttrVal($shash->{NAME}, 'temperatureOffset', 0);

            my $weekProfile = HiveHome_ParseWeekCmdString($weekString, $tempOffset);
            if (!defined($weekProfile))
            {
                $ret = "invalid weekprofile value - ".$weekProfile;
                Log(3, "_verifyWriteProductCommandArgs(${cmd}): Invalid command argument - ".$weekString);
            }
        }
        elsif ((lc($shash->{productType}) eq 'heating') and ($cmd eq 'holidaymode'))
        {
            # Three params
            #   args[0] = start date/time
            #   args[1] = end date/time
            #   args[2] = temp
            # Date/times in the format of YYYY-MM-DDTHH:MM

            if (!$args[0] || !$args[1] || !$args[2])
            {
                $ret = "holidaymode requires three parameters; start datetime, end datetime and temperature";
            }
        }
        elsif ((lc($shash->{productType}) eq 'heating') and ($cmd eq 'cancelholidaymode'))
        {
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'name'))
        {
            if (!$args[0])
            {
                $ret = "invalid value '${args[0]}', must contain a name";
            }
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'calibrate'))
        {
            if ($args[0])
            {
                if (lc($args[0]) ne 'start' && lc($args[0]) ne 'stop')
                {
                    $ret = "invalid value '${args[0]}', must be either start or stop";
                }
            }
            else
            {
                $ret = "missing argument value, must be either start or stop";
            }
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'valveposition'))
        {
            if (!$args[0])
            {
                $ret = "missing argument value, must be either horizontal or vertical";
            }
        }
        elsif ((lc($shash->{productType}) eq 'trvcontrol') and ($cmd eq 'childlock'))
        {
            if (!defined($args[0]) || ($args[0] != 0 && $args[0] != 1))
            {
                $ret = "missing argument value, must be either 0 or 1";
            }
        }
        elsif ((lc($shash->{productType}) eq 'heating') or (lc($shash->{productType}) eq 'trvcontrol'))
        {
            if ($cmd eq 'desiredtemperature')
            {
                # If the command is 'desiredTemperature' then the first argument can be translated into the command or a temperature for manual.
                if (HiveHome_IsValidTemperature($cmd))
                {
                    $args[0] = $cmd;
                    $cmd = 'manual';
                }
                else
                {
                    $cmd = $args[0];
                }
            }

            # Can have arguments of:
            #	SCHEDULE, MANUAL, OFF, BOOST
            if (($cmd eq 'schedule') or ($cmd eq 'off'))
            {
                # No args for these commands.
            }
            elsif ($cmd eq 'boost') 
            {
                # BOOST can be provided with or without parameters
                #       If no parameters then it will use the internals boostTemperature and boostDuration
                
                if (!defined($args[0]) || $args[0] eq '')
                { }
                elsif (!HiveHome_IsValidTemperature($args[0]))
                {
                    $ret = "invalid value '${args[0]}', must be a temperature value";
                }
                elsif (!HiveHome_IsValidNumber($args[1]))
                {
                    $ret = "invalid value '${args[1]}', must be a time in mins";
                }
            }
            elsif (($cmd eq 'manual') or ($cmd eq 'scheduleoverride'))
            {
                # MANUAL and SCHEDULEOVERRIDE next arg is temperature.
                # 		Can we get devices minimum and maximum temperature from device details
                #		and only allow whole or half decimal places			

                if (!HiveHome_IsValidTemperature($args[0]))
                {
                    $ret = "invalid value '${args[0]}', must be a temperature value";
                }
            }
            elsif ($cmd eq 'advanceschedule')
            { }
            elsif (lc($shash->{productType}) eq 'heating')
            {
                my $templist = join(",",map { HiveHome_SerializeTemperature($_/2) }  ( HiveHome_MinTemperature()*2..HiveHome_MaxTemperature()*2 ) );
                my $desOptions = "off,schedule,advanceSchedule,boost,${templist}";

                $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg manual:${templist} boost weekprofile holidaymode cancelholidaymode:noArg advanceSchedule:noArg scheduleOverride:${templist} desiredTemperature:${desOptions} ";
            }
            else
            {
                my $templist = join(",",map { HiveHome_SerializeTemperature($_/2) }  ( HiveHome_MinTemperature()*2..HiveHome_MaxTemperature()*2 ) );
                my $desOptions = "off,schedule,advanceSchedule,boost,${templist}";

                $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg manual:${templist} boost weekprofile advanceSchedule:noArg scheduleOverride:${templist} desiredTemperature:${desOptions} name calibrate:start,stop valveposition:horizontal,vertical childlock:0,1 ";
            }
        }
        elsif (lc($shash->{productType}) eq 'hotwater')
        {
            # Can have arguments of:
            #	SCHEDULE, ON, OFF, BOOST

            if (($cmd eq 'schedule') or ($cmd eq 'off') or ($cmd eq 'on'))
            {
            }
            elsif ($cmd eq 'boost')
            {
                # Verify duration is a number...
                if (!HiveHome_IsValidNumber($args[0]))
                {
                    $ret = "invalid value '${args[0]}', must be a time in mins";
                }
            }
            else
            {
                $ret = "unknown argument ${cmd} choose one of schedule:noArg off:noArg on:noArg boost:slider,15,15,420 weekprofile";
            }
        }
        else
        {
            Log(2, "HiveHome_Write_Product(${cmd}): Unkown product type: ".$shash->{productType});
            $ret = "unknown productType ".$shash->{productType}; 
        }
    }



    Log(5, "_verifyWriteProductCommandArgs: exit");

    return $ret;
}

sub _verifyWriteDeviceCommandArgs($$$$)
{
    my ($hash, $hiveHomeClient, $shash, $cmd, @args) = @_;

    Log(5, "_verifyWriteDeviceCommandArgs: enter");

    my $ret = undef;

    if (lc($cmd) eq lc('name'))
    {
        if (!$args[0])
        {
            $ret = "name expects a single argument!";
        }
    }
	else
	{
		$ret = "unknown argument ${cmd} choose one of name ";
	}

    Log(5, "_verifyWriteDeviceCommandArgs: exit");

    return $ret;
}

sub _verifyWriteCommandArgs($$$$)
{
    my ($hash, $shash, $cmd, @args) = @_;

    my $ret = undef;

    if (lc($shash->{TYPE}) eq lc('HiveHome_Action'))
    {
        $ret = _verifyWriteActionCommandArgs($hash, $shash, $cmd, @args);
    }
    elsif (lc($shash->{TYPE}) eq lc('HiveHome_Product'))
    {
        $ret = _verifyWriteProductCommandArgs($hash, $shash, $cmd, @args);
    }
    elsif (lc($shash->{TYPE}) eq lc('HiveHome_Device'))
    {
        $ret = _verifyWriteDeviceCommandArgs($hash, $shash, $cmd, @args);
    }

    return $ret;
}

sub HiveHome_Write($$$)
{
    my ($hash, @args) = @_;

    # Extract the device command details from the args array.
    my $shash = shift(@args);
    my $cmd = shift(@args);    

    my $name = $shash->{NAME};

    Log(5, "HiveHome_Write: enter");
    Log(4, "HiveHome_Write: ${name} ${cmd} ".int(@args));

    my $ret = undef;

    if ($cmd eq "?") {
        $ret = _verifyWriteCommandArgs($hash, $shash, $cmd, @args);
    } else {
        # Push the command onto the queue.
        my $args = {
                      "hash"  => $hash
                    , "shash" => $shash
                    , "cmd"   => $cmd
                    , "args"  => \@args
                };

        # TODO: How to report badly formated commands if we are offloading the request to the background?

        push( @{$hash->{helper}->{sendQueue}}, $args);
        Log(4, "HiveHome_Write: Adding item to queue: ".int(@{$hash->{helper}->{sendQueue}}));
        _writeSendNonBlocking($hash);
    }

    Log(5, "HiveHome_Write: exit");

    return $ret;
}

sub HiveHome_ctrl_Write($$$@)
{
    my ($hash, $shash, $cmd, @args) = @_;

    my $ret = undef;

    my $name = $shash->{NAME};

    Log(5, "HiveHome_ctrl_Write: enter");
    Log(4, "HiveHome_ctrl_Write: ${name} ${cmd} ".int(@args));

    my $hiveHomeClient = _getHiveHomeInterface($hash);
    if (!defined($hiveHomeClient) || !defined($hiveHomeClient->getToken()))
    {
		Log(1, "HiveHome_ctrl_Write: ".$hash->{username}." failed to logon to Hive");
		$hash->{STATE} = 'Disconnected';
	} 
	else 
	{
        # Determine the source of the message; Device, Product or Action
        #   First parameter of $msg

		Log(4, "HiveHome_ctrl_Write: ".$hash->{username}." succesfully connected to Hive");

        if (lc($shash->{TYPE}) eq lc('HiveHome_Action'))
        {
            $ret = HiveHome_Write_Action($hash, $hiveHomeClient, $shash, $cmd, @args);
        }
        elsif (lc($shash->{TYPE}) eq lc('HiveHome_Product'))
        {
            $ret = HiveHome_Write_Product($hash, $hiveHomeClient, $shash, $cmd, @args);
        }
        elsif (lc($shash->{TYPE}) eq lc('HiveHome_Device'))
        {
            $ret = HiveHome_Write_Device($hash, $hiveHomeClient, $shash, $cmd, @args);
        }


        ### Get the latest used token
        my $token = $hiveHomeClient->getToken();
        $hash->{HIVEHOME}{sessionToken} = $token->{token};
        $hash->{HIVEHOME}{refreshToken} = $token->{refreshToken};
        $hash->{HIVEHOME}{accessToken} = $token->{accessToken};

        if (!defined($ret))
        {
            # TODO: signal a refresh of the readings
            #		Not sure when though as 5 seconds isnt enough for them to be updated
            InternalTimer(gettimeofday()+2, "HiveHome_UpdateNodes", $hash, 0);
        }
    }

    Log(5, "HiveHome_ctrl_Write: exit");

    return $ret;
}

sub _writeSend($)
{
    my $data = shift;

    Log(5, "_writeSend: enter");

    Log(4, "_writeSend: ".$data->{hash}->{NAME}." ".$data->{shash}->{NAME}." ".$data->{cmd}." ".int(@{$data->{args}}));

    my $ret = HiveHome_ctrl_Write($data->{hash}, $data->{shash}, $data->{cmd}, @{$data->{args}});

    my $resp;
    $resp = "1" if (defined($ret));
    $resp = "0" if (!defined($ret));

    Log(5, "_writeSend: exit");

    return $data->{hash}->{NAME}."|${resp}";
}

sub _writeSendDone($)
{
    my ($string) = @_;
    my ($me, $ok) = split("\\|", $string);
    my $hash = $defs{$me};
  
    Log(4, "$me(_writeSendDone): message successfully send") if ($ok);
    Log(4, "$me(_writeSendDone): sending message failed") if (!$ok);
  
    delete($hash->{helper}{RUNNING_PID});
}

sub _writeSendAbort($)
{
    my $hash = shift;

    Log(2, "_writeSendAbort: Error. sending aborted.");

    delete($hash->{helper}{RUNNING_PID});
}

sub _writeSendNonBlocking($)
{
    my $hash = shift;
    my $me = $hash->{NAME};

    Log(5, "_writeSendNonBlocking: enter");

    RemoveInternalTimer($hash, "_writeSendNonBlocking");

    my $queueSize = int(@{$hash->{helper}->{sendQueue}});
    Log(4, "_writeSendNonBlocking: Queue size: ${queueSize}");

    return if ($queueSize <= 0); #nothing to do

    # This is suspect logic which can cause race conditions! What synchronisation tools exist within Perl?
    if (!exists($hash->{helper}{RUNNING_PID})) {
        my $data = shift(@{$hash->{helper}->{sendQueue}});

        $hash->{helper}{RUNNING_PID} = BlockingCall("_writeSend", $data, "_writeSendDone", 15, "_writeSendAbort", $hash);

    } else {
        Log(4, "_writeSendNonBlocking: Blocking call running - will try again later");
    }

    $queueSize = int(@{$hash->{helper}->{sendQueue}});
    InternalTimer(gettimeofday()+0.5, "_writeSendNonBlocking", $hash, 0) if ($queueSize > 0);

    Log(5, "_writeSendNonBlocking: exit");
}


1;

# Start of command ref

=pod
=item device
=item summary The HiveHome hub bridge
=begin html

<a name="HiveHome"></a>

<h3>HiveHome</h3>
<ul>
	<i>HiveHome</i> implements the bridge from your HiveHome account to your HiveHome devices.
	Once this device has successfully connected with your HiveHome account it will automatically create
	devices for each product, device and actions connected with your HiveHome account.<br>
	If the <a href="#autocreate">autocreate</a> module is enabled then all supported Hive devices will be automatically created.
	<br><br>
	Currently supported HiveHome products are:
	<ul>
		<li><i>Hub</i><br></li>
		<li><i>Boiler module</i><br></li>
		<li><i>Thermostat UI</i><br></li>
		<li><i>Radiator TRVs</i><br></li>
		<li><i>Actions</i><br></li>
	</ul>
	<br>
	<a name="HiveHomeDefine"></a>
	<b>Define</b>
	<ul>
        <code>define &lt;name&gt; HiveHome &lt;username&gt; &lt;password&gt;</code>
        <br><br>
        Example: <code>define myHiveHome HiveHome username password</code>
        <br><br>
        The credentials here are your HiveHome account credentials.<br>
        Note: This will not work if you have setup two factor authentication on your HiveHome account.<br>
	</ul>

	<br><br>
	<a name="HiveHomeReadings"></a>
	<b>Readings</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHomeSet"></a>
	<b>Set</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHomeGet"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>

	<br><br>
	<a name="HiveHomeAttributes"></a>
	<b>Attributes</b>
	<ul>
		N/A
	</ul>

</ul>

=end html

# End of commandref 
=cut
