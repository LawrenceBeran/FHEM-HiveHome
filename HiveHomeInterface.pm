package HiveHomeInterface;
use strict;
use warnings;

use HiveHomeAPI;
use JSON;
use Data::Dumper;
use Carp qw(croak);
use Math::Round;
use List::Util qw(first);

# Note: The API does not currently care whether the 'heating' or 'hotwater' path is specified as part
# of the /nodes/<heating or hotwater>/<id> endpoint for either heating or hotwater products.
#   A hotwater product id can be specified as part of the heating path and vis-versa.
#
# The API also doesnt respond in failure if invalid parameters are provided to it.
# Most values are tested for validity in this API to rule out errors of that kind.
#

my $heatingPath ='heating';
my $trvControlPath ='trvcontrol';
my $hotWaterPath ='hotwater';


my %validPaths = (
        lc($heatingPath) => 1
    ,   lc($trvControlPath) => 1
);

my $targetValue = 'target';
my $statusValue = 'status';

# HeatingPath is used for 
my %validType = (
        lc($heatingPath) => lc($targetValue)
    ,   lc($hotWaterPath) => lc($statusValue)
    ,   lc($trvControlPath) => lc($targetValue)
);


my $trvDevicePath = 'trv';
my $hubDevicePath = 'hub';
my $boilerModuleDevicePath = 'boilermodule';
my $thermostatuiDevicePath = 'thermostatui';

my %validDevicePaths = (
        lc($hubDevicePath) => 1
    ,   lc($trvDevicePath) => 1
    ,   lc($boilerModuleDevicePath) => 1
    ,   lc($thermostatuiDevicePath) => 1
);



sub new        # constructor, this method makes an object that belongs to class Number
{
    my $class = shift;          # $_[0] contains the class name

    croak "Illegal parameter list has odd number of values" 
        if @_ % 2;

    my %params = @_;

    my $self = {};              # the internal structure we'll use to represent
                                # the data in our class is a hash reference
    bless( $self, $class );     # make $self an object of class $class

    # This could be abstracted out into a method call if you 
    # expect to need to override this check.
    for my $required (qw{ userName password  }) {
        croak "Required parameter '$required' not passed to '$class' constructor"
            unless exists $params{$required};  
    }

    $self->{apiHive} = HiveHomeAPI->new(%params);

    return $self;        # a constructor always returns an blessed() object
}

sub getToken($)
{
    my $self = shift;

    if (!defined($self->{apiHive}))
    {
        $self->_log(1, "Unable to call HiveHome - (No API object)!");
    }
    else
    {
        return $self->{apiHive}->getToken();
    }
    return undef;
}

sub getDevices($)
{
    my $self = shift;

    my @devices = ();

    if (!defined($self->{apiHive}))
    {
        $self->_log(1, "Unable to call HiveHome - (No API object)!");
    }
    else
    {
        my $devicesAPI = $self->{apiHive}->apiGET('devices');

#        $self->_log(3, "HiveHomeInterface::getDevices - ".Dumper($devicesAPI));

        # For each device, get its id, parent and name
        foreach my $deviceAPI (@{$devicesAPI}) 
        {
            my $dev = {
                    id => $deviceAPI->{id}
                ,   type => $deviceAPI->{type}
                ,   name => $deviceAPI->{state}->{name}
                ,   parent => $deviceAPI->{parent}
                ,   internals => {
                        manufacturer => $deviceAPI->{props}->{manufacturer}
                    ,   model => $deviceAPI->{props}->{model}
                    ,   power => $deviceAPI->{props}->{power}
                }
                ,   readings => {
                        online => $deviceAPI->{props}->{online}
                    ,   firmwareVersion => $deviceAPI->{props}->{version}
                }
                ,   hhType => 'device'
            };

            # If the device is battery powered, get its battery level.
            if (lc $deviceAPI->{props}->{power} eq "battery")
            {
                # batteryLevel
                $dev->{readings}->{battery} = $deviceAPI->{props}->{battery};
            }

            # Get the signal if its defined.
            if (defined($deviceAPI->{props}->{signal}))
            {
                $dev->{readings}->{signal} = $deviceAPI->{props}->{signal};
            }

            # Get the zone if its defined (the zone can be under either state or prop).
            if (defined($deviceAPI->{props}->{zone}))
            {
                $dev->{internals}->{zone} = $deviceAPI->{props}->{zone};
            }
            elsif (defined($deviceAPI->{state}->{zone}))
            {
                $dev->{internals}->{zone} = $deviceAPI->{state}->{zone};
            }

            if (lc($deviceAPI->{type}) eq 'trv')
            {
                # For TRVs:
                # Get the devices related product Id.
                if (defined($deviceAPI->{state}->{control}))
                {
                    $dev->{internals}->{control} = $deviceAPI->{state}->{control};
                    $dev->{productId} = $deviceAPI->{state}->{control};
                }

                if (defined($deviceAPI->{state}->{childLock}))
                {
                    $dev->{internals}->{childLock} = $deviceAPI->{state}->{childLock};
                }

                if (defined($deviceAPI->{state}->{viewingAngle}))
                {
                    $dev->{internals}->{viewingAngle} = $deviceAPI->{state}->{viewingAngle};
                }

                if (defined($deviceAPI->{props}->{eui64}))
                {
                    $dev->{internals}->{eui64} = $deviceAPI->{props}->{eui64};
                }

                if (defined($deviceAPI->{state}->{mountingModeActive}))
                {
                    $dev->{internals}->{mountingModeActive} = $deviceAPI->{state}->{mountingModeActive};

                    if ($deviceAPI->{state}->{mountingModeActive})
                    {
                        if (defined($deviceAPI->{state}->{mountingMode}))
                        {
                            $dev->{internals}->{mountingMode} = $deviceAPI->{state}->{mountingMode};
                        }
                    }
                }

                if (defined($deviceAPI->{state}->{calibrationStatus}))
                {
                    $dev->{internals}->{calibrationStatus} = $deviceAPI->{state}->{calibrationStatus};
                }
            }

            push @devices, $dev;
        }
    }
    return @devices;
}

sub getProducts($)
{
    my $self = shift;

    my @products = ();

    if (!defined($self->{apiHive}))
    {
        $self->_log(1, "Unable to call HiveHome - (No API object)!");
    }
    else
    {
        my $productsAPI = $self->{apiHive}->apiGET('products');

#        $self->_log(3, "HiveHomeInterface::getProducts - ".Dumper($productsAPI));

        # For each product, get its id, parent and name
        foreach my $productAPI (@{$productsAPI}) 
        {
            my $prod = {
                    id => $productAPI->{id}
                ,   type => $productAPI->{type}
                ,   parent => $productAPI->{parent}
                ,   name => $productAPI->{state}->{name}
                ,   hhType => 'product'
            };

            # If the product is heating or hot water then its deviceId is the same as its parentId.
            if ($prod->{type} eq lc($heatingPath) or $prod->{type} eq $hotWaterPath)
            {
                $prod->{deviceId} = $productAPI->{parent}
            }

            # Test to see if the product is online, only some of the product info is available when it is offline
            if ($productAPI->{props}->{online})
            {
                $prod->{internals} = { 
                        pmz => $productAPI->{props}->{pmz}
                    ,   scheduleOverride => $productAPI->{props}->{scheduleOverride}
                    ,   frostProtection => $productAPI->{state}->{frostProtection}
                    ,   schedule => $self->_convertAPIScheduleToFHEM($productAPI->{state}->{schedule})
                };
                $prod->{readings} = {
                        mode => $productAPI->{state}->{mode}
                    ,   target => $productAPI->{state}->{target}
                    ,   working => $productAPI->{props}->{working}
                    ,   online => $productAPI->{props}->{online}
                }; 

                if (defined($productAPI->{props}->{temperature}))
                {
                    $prod->{readings}->{temperature} = $productAPI->{props}->{temperature};
                }

                # Get the zone if its defined.
                if (defined($productAPI->{props}->{zone}))
                {
                    $prod->{internals}->{zone} = $productAPI->{props}->{zone};
                }
                elsif (defined($productAPI->{state}->{zone}))
                {
                    # In trvcontrol products the zone is in the state container, not the props, not sure what is the difference.
                    # MAY NEED TO LOOK INTO THIS WHEN I HAVE MORE THAN ONE TRV OR IF I EVER GET MORE THAN ONE ZONE
                    $prod->{internals}->{zone} = $productAPI->{state}->{zone};
                }

                if (defined($productAPI->{props}->{maxEvents}))
                {
                    $prod->{internals}->{maxEvents} = $productAPI->{props}->{maxEvents};
                } 

                if (defined($productAPI->{props}->{trvs}))
                {
                    $prod->{internals}->{trvs} = $productAPI->{props}->{trvs};
                } 

                if (defined($productAPI->{state}->{boost}))
                {
                    # This could be null!
                    $prod->{internals}->{boost} = $productAPI->{state}->{boost};
                } 

                if (defined($productAPI->{props}->{previous}))
                {
                    $prod->{internals}->{previousMode} = $productAPI->{props}->{previous}->{mode};
                    if (defined($productAPI->{props}->{previous}->{target}))
                    {
                        $prod->{internals}->{previousMode} .= " ".$productAPI->{props}->{previous}->{target};
                    }
                }

                if (defined($productAPI->{props}->{capabilities}))
                {
                    $prod->{attr}->{capabilities} = "";
                    foreach my $cap (@{$productAPI->{props}->{capabilities}})
                    {
                        $prod->{attr}->{capabilities} .= $cap." ";
                    }
                }

                if (defined($productAPI->{props}->{readyBy}))
                {
                    $prod->{internals}->{readyBy} = $productAPI->{props}->{readyBy};
                }

                if (defined($productAPI->{props}->{scheduleOverride}))
                {
                    $prod->{internals}->{scheduleOverride} = $productAPI->{props}->{scheduleOverride};
                }

                if (defined($productAPI->{state}->{optimumStart}))
                {
                    $prod->{internals}->{optimumStart} = $productAPI->{state}->{optimumStart};
                }

                if (defined($productAPI->{state}->{autoBoost}))
                {
                    $prod->{internals}->{autoBoost} = $productAPI->{state}->{autoBoost};
                }

                if (defined($productAPI->{state}->{autoBoostTarget}))
                {
                    $prod->{internals}->{autoBoostTarget} = $productAPI->{state}->{autoBoostTarget};
                }

                if (defined($productAPI->{props}->{holidayMode}))
                {
                    $prod->{internals}->{holidayMode} = $productAPI->{props}->{holidayMode};
                    # Round the milliseconds away and convert to human readable strings
                    $prod->{internals}->{holidayMode}->{start} = $self->_convertEpochToDateString($prod->{internals}->{holidayMode}->{start} /= 1000);
                    $prod->{internals}->{holidayMode}->{end} = $self->_convertEpochToDateString($prod->{internals}->{holidayMode}->{end} /= 1000);
                }

                if ($prod->{type} eq lc($trvControlPath) and defined($productAPI->{props}->{trvs}[0]))
                {
                    # Assumption that there is only one TRV even though this is an array!
                    $prod->{deviceId} = $productAPI->{props}->{trvs}[0];
                }
            }
            else
            {
                # If the product is offline then the info provided is incomplete
                $prod->{readings} = {
                        online => $productAPI->{props}->{online}
                };

                # Sometimes when the product is offline, there is an error item. Not sure how menaingful the error is here though...
                if (defined($productAPI->{error}))
                {
                    $prod->{error} = $productAPI->{error};
                }
            }
            push @products, $prod;
        }
    }
    return @products;
}

sub getHolidayMode($)
{
    my $self = shift;

    my $resp = undef;

    if (!defined($self->{apiHive}))
    {
        $self->_log(1, "Unable to call HiveHome - (No API object)!");
    }
    else
    {
        $resp = $self->{apiHive}->apiGET('holiday-mode');
        if (defined($resp))
        {
            # Round the milliseconds away.
            if (defined($resp->{start}))
            {
                $resp->{start} /= 1000;
            }
            if (defined($resp->{end}))
            {
                $resp->{end} /= 1000;
            }
        }
    }
    return $resp;
}

# Date/times in the format of YYYY-MM-DD:HH:MM
sub setHolidayMode($$$$) 
{
    my $self = shift;
    my $startDateTime = shift;
    my $endDateTime = shift;
    my $temp = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $startDateTimeEpoch = $self->_convertDateStringToEpoch($startDateTime);
        my $endDateTimeEpoch = $self->_convertDateStringToEpoch($endDateTime);

        if (!defined($startDateTimeEpoch))
        {
            $ret = "invalid holidaymode start date value - ".$startDateTime;
            $self->_log(1, "HiveHome_Write_Product: Invalid start date argument - ".$startDateTime);
        }
        elsif (!defined($endDateTimeEpoch))
        {
            $ret = "invalid holidaymode end date value - ".$endDateTime;
            $self->_log(1, "HiveHome_Write_Product: Invalid end date argument - ".$endDateTime);
        }
        # The holiday has to start before it can finish!
        elsif ($endDateTimeEpoch > $startDateTimeEpoch)
        {
            my $currentTime = time;

            # Get the year from the provided start date time parameter
            my $currentYear = (localtime($currentTime))[5];
            my $startYear = (localtime($startDateTimeEpoch))[5];

            # Assumption is that you would not set a holiday in the future but no further 
            # ahead in time than one year
            if ($startDateTimeEpoch > $currentTime && $startYear <= ($currentYear + 1))
            {
                my $data = {
                        start => $startDateTime * 1000
                    ,   end => $endDateTimeEpoch * 1000
                    ,   temperature => $self->_getValidTemp($temp)
                };

                my $resp = $self->{apiHive}->apiPOST('holiday-mode', $data);
            }
        }
    }
    return $ret;
}

sub cancelHolidayMode($)
{
    my $self = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $resp = $self->{apiHive}->apiDELETE('holiday-mode');
        if (!$resp)
        {
            $self->_log(1, "cancelHolidayMode: Failed to make call");
            $ret = "Failed in call to HiveHome to cancel holiday mode!";
        }
        else
        {
            if (!$resp->{set})
            {
                $self->_log(1, "cancelHolidayMode: Interface returned failure");
                $ret = "HiveHome failed to cancel holiday mode!";
            }
            else
            {
                $self->_log(4, "cancelHolidayMode: Success");
            }
        }
    }
    return $ret
}


my %heatingModes = (
        SCHEDULE => 1
    ,   MANUAL => 1
    ,   OFF => 1
);

my %hotWaterModes = (
        SCHEDULE => 1
    ,   ON => 1
    ,   OFF => 1
);


sub setHeatingMode($$$$) 
{
    my $self = shift;
    my $id = shift;
    my $mode = shift;
    my $target = shift; #optional parameter, only required for MANUAL mode

    return $self->_setHeatingMode($heatingPath, $id, $mode, $target);
}

sub setHeatingBoostMode($$$$) 
{
    my $self = shift;
    my $id = shift;
    my $temp = shift;
    my $duration = shift;

    return $self->_setHeatingBoostMode($heatingPath, $id, $temp, $duration);
}

sub cancelHeatingBoostMode($$) 
{
    my $self = shift;
    my $id = shift;

    return $self->_cancelHeatingBoostMode($heatingPath, $id);
}

sub setTRVControlMode($$$$) 
{
    my $self = shift;
    my $id = shift;
    my $mode = shift;
    my $target = shift; #optional parameter, only required for MANUAL mode

    return $self->_setHeatingMode($trvControlPath, $id, $mode, $target);
}

sub setTRVControlBoostMode($$$$) 
{
    my $self = shift;
    my $id = shift;
    my $temp = shift;
    my $duration = shift;

    return $self->_setHeatingBoostMode($trvControlPath, $id, $temp, $duration);
}

sub cancelTRVControlBoostMode($$) 
{
    my $self = shift;
    my $id = shift;

    return $self->_cancelHeatingBoostMode($trvControlPath, $id);
}

# mode can be one of 
#   SCHEDULE, MANUAL, OFF
sub setHotWaterMode($$$) 
{
    my $self = shift;
    my $id = shift;
    my $mode = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    elsif (!exists($hotWaterModes{uc($mode)}))
    {
        $self->_log(4, "setHotWaterMode: Unrecognised mode: ${mode}");
        $ret = "Invalid hot water mode, can only be one of; !";
    }
    else
    {
        my $data = {
            mode => uc($mode)
        };

        my $resp = $self->{apiHive}->apiPOST('nodes/hotwater/'.$id, $data);
    }
    return $ret;
}

sub setHotWaterBoostMode($$$) 
{
    my $self = shift;
    my $id = shift;
    my $duration = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $data = {
                mode => 'BOOST'
            ,   boost => $self->_getValidBoostDuration($duration)
        };

        my $resp = $self->{apiHive}->apiPOST('/nodes/hotwater/'.$id, $data);
    }
    return $ret;
}

sub cancelHotWaterBoostMode($$) 
{
    my $self = shift;
    my $id = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $resp = $self->{apiHive}->apiGET('products');
        if (!defined($resp))
        {
            $self->_log(4, "cancelHotWaterBoostMode: Failed to get products!");
            $ret = "Failed to get previous hot water mode!";
        }
        else
        {
            my ($item) = first { $id eq $_->{id} } @$resp;
            if (!defined($item))
            {
                $self->_log(4, "cancelHotWaterBoostMode: could not find the required item by id: ".$id);
                $ret = "Failed to get previous hot water mode!";
            }
            else
            {
                if (uc($item->{state}->{mode}) eq 'BOOST')
                {
                    $ret = $self->setHotWaterMode($id, $item->{props}->{previous}->{mode});
                }
                else
                {
                    # The specified item is not currently in BOOST mode
                    $ret = undef;
                }
            }
        }
    }
    return $ret;
}

sub setHeatingSchedule($$$) 
{
    my $self = shift;
    my $id = shift;
    my $schedule = shift;

    $self->_setSchedule($heatingPath, $id, $schedule);
}

sub setTRVControlSchedule($$$) 
{
    my $self = shift;
    my $id = shift;
    my $schedule = shift;

    $self->_setSchedule($trvControlPath, $id, $schedule);
}

sub setHotWaterSchedule($$$) 
{
    my $self = shift;
    my $id = shift;
    my $schedule = shift;

    $self->_setSchedule($hotWaterPath, $id, $schedule);
}




sub getActions($) 
{
    my $self = shift;

    my @actions = ();

    if (!defined($self->{apiHive}))
    {
        $self->_log(1, "Unable to call HiveHome - (No API object)!");
    }
    else
    {
        my $actionsAPI = $self->{apiHive}->apiGET('actions');

        # For each device, get its id, parent and name
        foreach my $actionAPI (@{$actionsAPI}) 
        {
            my $action = {
                    id => $actionAPI->{id}
                ,   name => $actionAPI->{name}
                ,   enabled => $actionAPI->{enabled} 
            };

            push @actions, $action;
        }
    }
    return @actions;
}

sub activateAction($$) 
{
    my $self = shift;
    my $id = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $data = {
            activated => JSON::true
        };

        my $resp = $self->{apiHive}->apiPOST('actions/'.$id.'/quick-action', $data);
    }
    return $ret;
}

sub enableAction($$$) 
{
    my $self = shift;
    my $id = shift;
    my $state = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
#
# TODO
#

#        my $data = {
#            activated => JSON::true
#        };

#        my $resp = $self->{apiHive}->apiPOST('actions/'.$id.'/quick-action', $data);
    }
    return $ret;
}






sub setFrostProtection($$$$) 
{
    my $self = shift;
    my $path = shift;   # path matches to productType
    my $id = shift;
    my $temp = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    elsif (!exists($validPaths{lc($path)}))
    {
        $self->_log(4, "setFrostProtection: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        my $data = {
            frostProtection => $self->_getValidTemp($temp)
        };

        my $resp = $self->{apiHive}->apiPOST('nodes/'.$path.'/'.$id, $data);
    } 
    return $ret;
}



########################################################
# Helper

sub _convertAPIScheduleToFHEM($$) 
{
    my $self = shift;
    my $schedule = shift;

#    my %dayHash = (mon => "monday", tue => "tuesday", wed => "wednesday", thu => "thursday", fri => "friday", sat => "saturday", sun => "sunday");
    my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);

    my $test = {};

    foreach my $day (@daysofweek) 
    {
        my @values;
        foreach my $scheduleItem (@{$schedule->{$day}})
        {
            if (defined($scheduleItem->{value}->{target}))
            {
                # If heating or trv
                push(@values, $self->_convertAPITimeToFHEM($scheduleItem->{start})."-".$scheduleItem->{value}->{target}."°C");
            }
            elsif (defined($scheduleItem->{value}->{status}))
            {
                # If hotwater
                push(@values, $self->_convertAPITimeToFHEM($scheduleItem->{start})."-".$scheduleItem->{value}->{status});
            }
        }
        $test->{"${day}"} = join(' / ', @values);
    }
    return $test;
}

# Date/times in the format of YYYY-MM-DD:HH:MM
sub _convertDateStringToEpoch($$)
{
    my $self = shift;
    my $dateTimeString = shift;

    $self->_log(4, "_convertDateStringToEpoch: enter - ".$dateTimeString);

    my ($year, $month, $day, $hour, $mins) = split(/[-:T]/, $dateTimeString);
    $self->_log(4, "_convertDateStringToEpoch: ${year}-${month}-${day} ${hour}:${mins}");
    
    my $startDate = undef;
    eval
    {
        $startDate = timelocal(0, $mins, $hour, $day, $month-1, $year);
    };

    if (defined($startDate))
    {
        if ((localtime($startDate))[3] != $day and (localtime($startDate))[4] != $month and (localtime($startDate))[5] != $year)
        {
            $startDate = undef;
        }
    }
    return $startDate;
}

# Date/times returned in the format of YYYY-MM-DD:HH:MM
sub _convertEpochToDateString($$)
{
    my $self = shift;
    my $dateTime = shift;

    $self->_log(4, "_convertEpochToDateString: enter - ".$dateTime);

    my ($min, $hour, $day, $month, $year) = (localtime($dateTime))[1,2,3,4,5];
    return sprintf("%04d-%02d-%02d %02d:%02d", $year+1900, $month-1, $day, $hour, $min);
}

# The schedule stores time in minutes (1,440 per day, 60 per hour)
sub _convertAPITimeToFHEM($$) 
{
    my $self = shift;
    my $time = shift;

    if (!defined($time) || $time == 0)
    {
        return "00:00";
    }
    elsif ($time >= 1439)
    {
        return "23:59"
    }
    {
        use integer;
        return sprintf("%02d:%02d", $time/60, $time%60);
    }
}

sub _getMinHeatingTemp($) 
{
    my $self = shift;

    return 5;
}

sub _getMaxHeatingTemp($) 
{
    my $self = shift;

    return 32;
}

sub _getValidStatus($$) 
{
    my $self = shift;
    my $s = shift; 

    if ($s =~ s/^(ON|OFF)$/\U$1/i) 
    { 
        return $s; 
    } 
    return undef;
}

sub _getValidTemp($$) 
{
    my $self = shift;
    my $temp = shift;

    my $ret = undef;

    if ($temp < $self->_getMinHeatingTemp())
    {
        $ret = $self->_getMinHeatingTemp();
    }
    elsif ($temp > $self->_getMaxHeatingTemp())
    {
        $ret = $self->_getMaxHeatingTemp();
    }
    else
    {
        # Ensure only whole or half numbers are provided.
        $ret = round($temp * 2) / 2;
    }
    return $ret;
}

# This takes a time in the format of 'HH:MM' and converts it to number of minutes
sub _getTimeInMinutes($$) 
{
    my $self = shift;
    my $time = shift;

    my $ret = undef;

    my ($hour, $min) = split(':', $time);

    if (defined($hour) && defined($min))
    {
        # We could validate the time as the return cant be less than 0 or more than 1440.
        $ret = $hour*60 + $min;
    }
    return $ret;
}

my $minBoostDuration = 10; # 10 mins
my $maxBoostDuration = 420; # 7 hours (almost inline with the android app)

sub _getValidBoostDuration($$) 
{
    my $self = shift;
    my $duration = shift;

    my $ret = undef;

    if ($duration < $minBoostDuration)
    {
        $ret = $minBoostDuration;
    }
    elsif ($duration > $maxBoostDuration)
    {
        $ret = $maxBoostDuration;
    }
    else
    {
        $ret = $duration;
    }
    return $ret;
}

sub _trim($) 
{ 
    my $s = shift; 
    $s =~ s/^\s+|\s+$//g; 
    return $s 
};

sub _log($$$)
{
    my ( $self, $loglevel, $text ) = @_;

    $self->{apiHive}->_log($loglevel, $text)
}
######################
# Generics helper methods

sub _getMaxNumbHeatingElements($) 
{
    my $self = shift;

    return 6;
}

sub _convertScheduleStringToJSON($$$) 
{
    my $self = shift;
    my $scheduleType = shift;
    my $scheduleString = shift;

    my $scheduleJSON = {};

    if (!exists($validType{lc($scheduleType)}))
    {
        $self->_log(4, "_convertScheduleStringToJSON: Unrecognised schedule type: ${scheduleType}");
    }
    else
    {
		my %dayHash = (mon => "monday", tue => "tuesday", wed => "wednesday", thu => "thursday", fri => "friday", sat => "saturday", sun => "sunday",
                       monday => "monday", tuesday => "tuesday", wednesday => "wednesday", thursday => "thursday", friday => "friday", saturday => "saturday", sunday => "sunday" );
		my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);

        # Split the string into its component (day) parts 
        my @array = split(/(monday|mon|tuesday|tue|wednesday|wed|thursday|thu|friday|fri|saturday|sat|sunday|sun)/i, _trim($scheduleString));
        # Remove the first element, which is blank
        shift(@array);

        my $valueName = $validType{lc($scheduleType)};

        my $valid_string = 1;

        for (my $day = 0;$day <= $#array && $valid_string;$day += 2)
        {
            $self->_log(4,"_convertScheduleStringToJSON: Idx: ".$day." of ".$#array);

            # Verify that '$array[$day]' contains a valid day string
            if (!exists($dayHash{lc($array[$day])}))
            {
                $self->_log(1,"_convertScheduleStringToJSON: Invalid day element '".lc($array[$day])."'");
                $valid_string = undef;
            } 
            else 
            {
                $self->_log(4,"_convertScheduleStringToJSON: Day: ".$array[$day]);
                $self->_log(4,"_convertScheduleStringToJSON: Sch: "._trim($array[$day+1]));

                my (@value, @time);

                my $i;
                push @{ $i++ % 2 ? \@time : \@value }, $_ for split(/,/, _trim($array[$day+1]));
                # TODO: Verify elements, 
                #       there should be one more temp than time or
                #                the first time must be 00:00 or 0:00
                #       times should be in the format of ([0-9]|0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]
                #       temp should be greater than min temp and less than max temp (defined in object)
                #               in the format /^\d*\.?[0|5]$/
                #       There should only be a certain number of variables in the arrays
                #               The number is defined in the Hive thermostat node

                
                #
                # TODO: Do not allow more than 6 transitions... Do not change the number of transitions
                #		Same rules apply for water
                
                

                # Add the first time schedule, this is always midnight!
                unshift(@time, '00:00');

                # No temp value, default it to 18.
                if (scalar(@value) == 0) 
                {
                    if ($valueName eq $targetValue)
                    {
                        unshift(@value, 18);
                    } else {
                        unshift(@value, 'OFF');
                    }
                }
                
                # Validate the number of elements in the temp array
                if (scalar(@value) != scalar(@time)) 
                {
                    $self->_log(1,"_convertScheduleStringToJSON: The number of temp elements does not match the time elements.");
                    $valid_string = undef;
                } 
                else 
                {
                    my $maxNumbHeatingElements = $self->_getMaxNumbHeatingElements();

                    # Cannot add more elements than defined
                    if (scalar(@value) > $maxNumbHeatingElements) 
                    {
                        $self->_log(1, "_convertScheduleStringToJSON: Too many elements: ".scalar(@value));
                        $valid_string = undef;
                    } 
                    elsif (scalar(@value) < $maxNumbHeatingElements) 
                    {
    #                    $self->_log(2, "_convertScheduleStringToJSON: Not enough elements: ".scalar(@value));
                        # If the arrays do not have enough values, pad them out with the last element 
    #                        push @value, ($value[-1]) x ($maxNumbHeatingElements - @value);
    #                        push @time, ($time[-1]) x ($maxNumbHeatingElements - @time);
    #                    $self->_log(3, "_convertScheduleStringToJSON: Padded to: ".scalar(@value));
                    }

                    my $prev_time = 0;
                    for my $i ( 0 .. $#value)
                    {
                        my $time_ = $self->_getTimeInMinutes(_trim($time[$i]));
                        my $value_ = ($valueName eq $targetValue) 
                            ? $self->_getValidTemp(_trim($value[$i]))
                            : $self->_getValidStatus(_trim($value[$i]));

                        if (!defined($time_)) {
                            $self->_log(1,"_convertScheduleStringToJSON: Time '".$time[$i]."' is not valid");
                            $valid_string = undef;
                        } elsif ($time_ < $prev_time) {
                            $self->_log(1,"_convertScheduleStringToJSON: Time '".$time_."' is earlier than previous time '".$prev_time);
                            $valid_string = undef;
                        } elsif (!defined($value_)) {
                            $self->_log(1,"_convertScheduleStringToJSON: Value '".$value[$i]."' is not valid");
                            $valid_string = undef;
                        } else {
                            # Cache the current time for use in the next iteration
                            $prev_time = $time_;

                            $scheduleJSON->{schedule}->{$dayHash{lc($array[$day])}}[$i]->{start} = $time_;
                            $scheduleJSON->{schedule}->{$dayHash{lc($array[$day])}}[$i]->{value}->{$valueName} = $value_;
                        }

                        # If string invalid, break out of loop
                        if (!$valid_string) {
                            last;
                        }
                    }
                }
            }
        }

        # Verify that all days have been defined in the schedule. Hive does not like it if any are missing!
        foreach my $day (@daysofweek)
        {
            if (!defined($scheduleJSON->{schedule}->{$day}))
            {
                $self->_log(1,"_convertScheduleStringToJSON: The schedule for '".$day."' has not been provided");
                $valid_string = undef;
            }
        }

        if (!defined($valid_string))
        {
           $scheduleJSON = undef; 
        }
    }
    return $scheduleJSON;
}

sub _scheduleOverride($$$$)
{
    my $self = shift;
    my $path = shift;
    my $id = shift;
    my $target = shift;

    my $ret = undef;

    # Only valid for TRVs and Heating, not for hotwater
    if (!defined($self->{apiHive}))
    {
        $self->_log(2, "_advanceSchedule: Unable to call HiveHome - (No API object)!");
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    elsif (!exists($validPaths{lc($path)}))
    {
        $self->_log(2, "_advanceSchedule: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        if (defined($target))
        {
            $target = $self->_getValidTemp($target);
        }
        else
        {
            # If no target temperature provided, default it to 20.
            $target = 20;
        }

        my $data = {
            "target" => $target
        };

        my $resp = $self->{apiHive}->apiPOST('nodes/'.$path.'/'.$id, $data);
    }
    return $ret;
}

sub _advanceSchedule($$$)
{
    my $self = shift;
    my $path = shift;
    my $id = shift;

    my $ret = undef;

    # Only valid for TRVs and Heating, not for hotwater
    if (!defined($self->{apiHive}))
    {
        $self->_log(2, "_advanceSchedule: Unable to call HiveHome - (No API object)!");
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    elsif (!exists($validPaths{lc($path)}))
    {
        $self->_log(2, "_advanceSchedule: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        my $resp = $self->{apiHive}->apiGET('products');
        if (!defined($resp))
        {
            $self->_log(2, "_advanceSchedule: Failed to get products!");
            $ret = "Failed to get products from HiveAPI!";
        }
        else
        {
            my ($item) = first { $id eq $_->{id} } @$resp;
            if (!defined($item))
            {
                $self->_log(2, "_advanceSchedule: could not find the required product by id: ".$id);
                $ret = "Failed to find request product from HiveAPI!";
            }
            else
            {
                if (!$item->{props}->{online})
                {
                    $self->_log(2, "_advanceSchedule: specified product is offline: ".$id);
                    $ret = "Product is offline!";
                }
                else
                {
                    my @daysofweek = qw(sunday monday tuesday wednesday thursday friday saturday);
                    my ($min, $hour, $wday) = (localtime())[1,2,6];

                    # Get todays date....
                    my $day = $daysofweek[$wday];
                    # Get the current day mins
                    my $mins = ($hour * 60) + $min;

                    
                    $self->_log(4, "_advanceSchedule: Day: ${day} mins: ${mins}");

                    # TODO: Check error status if items have been found?
                    #       What happens if the next schedule event is on the following day.

                    # Find the first schedule item that time is greater than the current time.
                    my $daySchedule = $item->{state}->{schedule}->{$day};

                    $self->_log(4, "_advanceSchedule: - ".Dumper($daySchedule));


                    my ($scheduleItem) = first { $mins < $_->{start} } @$daySchedule;

                    # Assumption that if no schedule item was found then we are on the last schedule event of the day.
                    if (!defined($scheduleItem))
                    {
                        $self->_log(4, "_advanceSchedule: During last event of today, using first event of tomorrow!");
                        # Get tomorrows first scheduled event
                        $wday += 1;
                        $wday = 0 if ($wday > 6);
                        $scheduleItem = $item->{state}->{schedule}->{$daysofweek[$wday]}[0];
                    }

                    if (defined($scheduleItem))
                    {
                        $self->_log(4, "_advanceSchedule: - ".Dumper($scheduleItem));

                        my $data = {
                            "target" => $scheduleItem->{value}->{target}
                        };

                        my $resp = $self->{apiHive}->apiPOST('nodes/'.$path.'/'.$id, $data);
                    }
                }
            }
        }
    }
}


sub _setSchedule($$$$) {
    my $self = shift;
    my $path = shift;
    my $id = shift;
    my $scheduleString = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    if (!exists($validType{lc($path)}))
    {
        $self->_log(4, "_setSchedule: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        my $scheduleJSON = $self->_convertScheduleStringToJSON($path, $scheduleString);
        if (defined($scheduleJSON))
        {
            my $resp = $self->{apiHive}->apiPOST('nodes/'.$path.'/'.$id, $scheduleJSON);
        }
        else
        {
            $ret = "Badly formatted schedule string!";
        }
    }
    return $ret;
}


# mode can be one of 
#   SCHEDULE, MANUAL, OFF
sub _setHeatingMode($$$$$)
{
    my $self = shift;
    my $path = shift;
    my $id = shift;
    my $mode = shift;
    my $target = shift; #optional parameter, only required for MANUAL mode

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    if (!exists($validPaths{lc($path)}))
    {
        $self->_log(4, "_setHeatingMode: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    elsif (!exists($heatingModes{uc($mode)}))
    {
        $self->_log(4, "_setHeatingMode: Unrecognised mode: ${mode}");
        $ret = "Invalid heating mode!";
    }
    else
    {
        my $data = {
            mode => uc($mode)
        };

        if (uc($mode) eq 'MANUAL')
        {
            if (defined($target))
            {
                $target = $self->_getValidTemp($target);
            }
            else
            {
                # If no target temperature provided, default it to 20.
                $target = 20;
            }

            $data->{target} = $target;
        }

        my $resp = $self->{apiHive}->apiPOST('nodes/'.$path.'/'.$id, $data);
    }
    return $ret;
}

sub _setHeatingBoostMode($$$$$)
{
    my $self = shift;
    my $path = shift;
    my $id = shift;
    my $temp = shift;
    my $duration = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    if (!exists($validPaths{lc($path)}))
    {
        $self->_log(4, "_setHeatingMode: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        my $data = {
                mode => 'BOOST'
            ,   boost => $self->_getValidBoostDuration($duration)
            ,   target => $self->_getValidTemp($temp)
        };

        my $resp = $self->{apiHive}->apiPOST('/nodes/'.$path.'/'.$id, $data);
    }
    return $ret;
}

sub _cancelHeatingBoostMode($$$) 
{
    my $self = shift;
    my $path = shift;
    my $id = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    if (!exists($validPaths{lc($path)}))
    {
        $self->_log(4, "_setHeatingMode: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        # TODO: Get current items previous state details
        #       Get items Products
        my $resp = $self->_apiGET('products');

        if (!defined($resp))
        {
            $self->_log(4, "_cancelBoostMode: Failed to get products!");
            $ret = "Failed to get previous heating mode!";
        }
        else
        {
            my ($item) = first { $id eq $_->{id} } @$resp;
            if (!defined($item))
            {
                $self->_log(2, "_cancelBoostMode: could not find the required item by id: ".$id);
                $ret = "Failed to get previous heating mode!";
            }
            else
            {
                if (!$item->{props}->{online})
                {
                    $self->_log(2, "_cancelBoostMode: specified product is offline: ".$id);
                    $ret = "Failed to get previous heating mode!";
                }
                elsif (uc($item->{state}->{mode}) eq 'BOOST')
                {
                    my $resp = $self->_setHeatingMode($path, $id, $item->{props}->{previous}->{mode}, $item->{props}->{previous}->{target});
                }
                else
                {
                    # The specified item is not currently in BOOST mode
                    $ret = undef;
                }
            }
        }
    }
    return $ret;
}

sub _setDeviceName($$$$)
{
    my $self = shift;
    my $path = shift;
    my $id = shift;
    my $name = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    elsif (!exists($validDevicePaths{lc($path)}))
    {
        $self->_log(4, "_setDeviceName: Unrecognised path: ${path}");
        $ret = "Invalid product type!";
    }
    else
    {
        my $data = {
                name => $name
        };

        my $resp = $self->{apiHive}->apiPOST('/nodes/'.$path.'/'.$id, $data);
    }
    return $ret;    
}

sub _setOptimumStart($$$)
{
    my $self = shift;
    my $id = shift;
    my $activate = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $data = {
                optimumStart => JSON::true
        };

        if (!$activate)
        {
            $data->{optimumStart} = JSON::false;
        }

        my $resp = $self->{apiHive}->apiPOST('/nodes/heating/'.$id, $data);
    }
    return $ret;
}

sub trvCalibrate($$$)
{
    my $self = shift;
    my $id = shift;
    my $calibrateTRV = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    else
    {
        my $data = {
                calibrationStatus => "CALIBRATING"
        };

        if (!$calibrateTRV)
        {
            $data->{calibrationStatus} = "CANCEL_CALIBRATION";
        }        

        my $resp = $self->{apiHive}->apiPOST('/nodes/trv/'.$id, $data);
    }
    return $ret;
}

my $horizontal = "horizontal";
my $vertical = "vertical";

my %validViewingAngels = (
        lc($horizontal) => 1
    ,   lc($vertical) => 1
);


sub setTRVViewingAngle($$$)
{
    my $self = shift;
    my $id = shift;
    my $angle = shift;

    my $ret = undef;

    if (!defined($self->{apiHive}))
    {
        $ret = "Unable to call HiveHome - (No API object)!";
    }
    elsif (!exists($validViewingAngels{lc($angle)}))
    {
        $self->_log(4, "_setDeviceName: Unrecognised viewing angle: ${angle}");
        $ret = "Invalid viewing angle!";
    }    
    else
    {
        # Default to horizontal
        my $data = {
                viewingAngle => "ANGLE_0"
        };

        if (lc($angle) eq lc($vertical))
        {
            $data->{viewingAngle} = "ANGLE_180";
        }        

        my $resp = $self->{apiHive}->apiPOST('/nodes/trv/'.$id, $data);
    }
    return $ret;
}


1;