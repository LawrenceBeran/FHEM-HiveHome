#
use strict;
use warnings;
use utf8;











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

sub _is1stTimeBefore2ndTime($$) 
{
	my ($time1, $time2) = @_;
    return 1 if (!defined($time2) || $time1->{hour} < $time2->{hour} || ($time1->{hour} == $time2->{hour} && $time1->{min} < $time2->{min}));
    return 0;
}

sub HiveHome_GetWeekDay($)
{
	my ($str) = @_;

	my $weekDay=undef;
	my $timenum;

	if (defined($str)) {
		my @a = split("[T: -]", $str);
		$timenum=mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);	
	} else {
		$timenum=time;
	}

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($timenum);
	my @weekdays = qw(monday tuesday wednesday thursday friday saturday sunday);
	$weekDay = $weekdays[$wday - 1];
  
 	Log(4, "Weekday: ${weekDay}"); 
  
	return $weekDay;
}

sub _mergeElement1WithHottestTemperature($$)
{
	my ($element1, $element2) = @_;
    # Default is to return element1
    my $retElement = $element1;

    if (defined($element2) && $element2->{temp} > $element1->{temp}) {
        $retElement->{temp} = $element2->{temp};
        $retElement->{element} = $retElement->{time}."-".$retElement->{temp};
    }
    return $retElement;
}

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

#                Log(1, "Heating ".Dumper(@heatingDayElements));
#                Log(1, "TRV     ".Dumper(@trvDayElements));

                # Get the first heating and trv elements. These will both be for time 00:00
                my $trvElement = shift(@trvDayElements);
                my $heatingElement = shift(@heatingDayElements);

                # Previous read elements.
                my $trvElementPrevious = $trvElement;
                my $heatingElementPrevious = $heatingElement;

                # Last added element.
                my $lastAddedElement = undef;

                my %ELEMENT_TYPE = (
                        HEATING => 1
                    ,   TRV => 2
                );

                # Last element type added.
                my $lastAddedElementType = undef;

                my @retDayElements;

                # Assumption is that TRV from is always equal to or later than Heating from 
                my $finished = 0;
                while ($finished == 0)
                {
                    if ((defined($heatingElement) && defined($trvElement)) && ($heatingElement->{time} eq $trvElement->{time}))
                    {
                        # If both elements are at the same time.
                        # Then add the hotter of the two to the output array.

                        if ($trvElement->{temp} > $heatingElement->{temp}) {
                            $lastAddedElement = $trvElement;
                            $lastAddedElementType = $ELEMENT_TYPE{TRV};
                        } else {
                            $lastAddedElement = $heatingElement;
                            $lastAddedElementType = $ELEMENT_TYPE{HEATING};
                        }
                        _insertNewDayElement(\@retDayElements, $lastAddedElement);
                        # Cache the current elements as the previous
                        $trvElementPrevious = $trvElement;
                        $heatingElementPrevious = $heatingElement;
                        # Get the next TRV element.
                        $trvElement = shift(@trvDayElements);                            
                        $heatingElement = shift(@heatingDayElements);
                    }
                    elsif (defined($trvElement) && _is1stTimeBefore2ndTime($trvElement, $heatingElement))
                    {
                        # If the next element in chronological order is the trvElement
                        if (!defined($lastAddedElement) || ($trvElement->{temp} > $lastAddedElement->{temp})) {
                            # If its temperature is greater than the last added element's temperature
                            $lastAddedElement = $trvElement;
                            _insertNewDayElement(\@retDayElements, $lastAddedElement);
                            $lastAddedElementType = $ELEMENT_TYPE{TRV};
                        } elsif ((defined($lastAddedElementType) && $lastAddedElementType == $ELEMENT_TYPE{TRV})
                                || ($trvElement->{temp} >= $heatingElementPrevious->{temp})) {
                           # If the last added element was also a trv element or its temperature is equal or greater than the previous heating element.
                            $lastAddedElement = $trvElement;
                            if ($heatingElementPrevious->{temp} > $trvElement->{temp})
                            {
                                $lastAddedElement->{temp} = $heatingElementPrevious->{temp};
                                $lastAddedElement->{element} = $lastAddedElement->{time}."-".$lastAddedElement->{temp};
                                $lastAddedElementType = $ELEMENT_TYPE{HEATING};
                            }
                            _insertNewDayElement(\@retDayElements, $lastAddedElement);
                        }
                        $trvElementPrevious = $trvElement;
                        $trvElement = shift(@trvDayElements);                            
                    } 
                    elsif (defined($heatingElement) && _is1stTimeBefore2ndTime($heatingElement, $trvElement))
                    {
                        # If the next element in chronological order is the heatingElement
                        if (!defined($lastAddedElement) || ($heatingElement->{temp} > $lastAddedElement->{temp})) {
                            # If its temperature is greater than the last added element's temperature
                            $lastAddedElement = $heatingElement;
                            _insertNewDayElement(\@retDayElements, $lastAddedElement);
                            $lastAddedElementType = $ELEMENT_TYPE{HEATING};
                        } elsif ((defined($lastAddedElementType) && $lastAddedElementType == $ELEMENT_TYPE{HEATING})
                                    || ($heatingElement->{temp} >= $trvElementPrevious->{temp})) {
                            # If the last added element was also a heating element or its temperature is equal or greater than the previous TRV element.
                            $lastAddedElement = $heatingElement;
                            if ($trvElementPrevious->{temp} > $heatingElement->{temp})
                            {
                                $lastAddedElement->{temp} = $trvElementPrevious->{temp};
                                $lastAddedElement->{element} = $lastAddedElement->{time}."-".$lastAddedElement->{temp};
                                $lastAddedElementType = $ELEMENT_TYPE{TRV};
                            }
                            _insertNewDayElement(\@retDayElements, $lastAddedElement);                            
                        }
                        $heatingElementPrevious = $heatingElement;
                        $heatingElement = shift(@heatingDayElements);
                    }
                    else
                    {
                        # No more elements in either array. Time to finish!
                        $finished = 1;
                    }
                }

                # Check if the new day schedule has the allowed number of elements!
                if (defined($hiveHomeClient) && $hiveHomeClient->_getMaxNumbHeatingElements() >= $#retDayElements)
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


sub Log
{
    # This subroutine mimics the interface of the FHEM defined Log so that the test does not crash.
    my $var = '';
}



# Get todays shortname
my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
my $day = HiveHome_GetWeekDay(undef);


my %schedules;
#$schedules{"00:00-15 / 06:30-21 / 08:00-17 / 15:00-17 / 18:00-21 / 23:00-15"} = 1;
#$schedules{"00:00-15 / 06:15-20 / 08:30-15 / 17:00-20 / 23:00-15 / 23:55-15"} = 1;
#$schedules{"00:00-18 / 06:15-21 / 07:30-17 / 15:00-20 / 18:00-21 / 23:00-17"} = 1;
#$schedules{"00:00-15 / 08:00-20 / 22:00-15"} = 1;

# The following does not work!
$schedules{"00:00-15 / 06:30-20.5 / 08:00-19 / 18:00-20.5 / 23:00-15"} = 1;
$schedules{"00:00-18 / 06:30-20 / 09:00-19 / 15:00-20 / 18:00-20 / 23:00-17"} = 1;
$schedules{"00:00-15 / 06:30-20 / 08:00-20 / 18:00-20.5 / 23:00-15"} = 1;
$schedules{"00:00-15 / 06:30-20 / 08:00-18 / 18:00-20 / 23:00-15 / 23:55-15"} = 1;


my $hiveHomeClient = undef;

# Combine the unique schedules into a single schedule
my $heatingSchedule;
foreach my $schedule (keys %schedules) {
    Log(1, "HiveHome_SetZoneScheduleByZoneTRVSchedules: TRV is part of zone: ${schedule}");
    $heatingSchedule = _mergeDayHeatingShedule($hiveHomeClient, $day, $heatingSchedule, $schedule);
}

