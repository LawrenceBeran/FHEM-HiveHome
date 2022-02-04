package main;

use strict;
use warnings;

use Time::Local;


sub hhc_trim($) 
{ 
    my $s = shift; 
    $s =~ s/^\s+|\s+$//g; 
    return $s 
};

sub hhc_modifyTemperature($$$) {
	my ($elementHeating, $temperature, $addCentigrade) = @_;

    $elementHeating->{temp} = $temperature;
    $elementHeating->{element} = $elementHeating->{time}."-".$elementHeating->{temp};

    if (defined($addCentigrade)) {
        $elementHeating->{element} = $elementHeating->{element}."°C";
    }
    return $elementHeating;
}

sub hhc_extractHeatingElements($)
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

sub hhc_removeTemperatureOffsetFromSchedule($$) {
	my ($temperatureOffset, $daySchedule) = @_;

	my @heatingDayElements = hhc_extractHeatingElements($daySchedule);

	foreach my $element (@heatingDayElements) {
        hhc_modifyTemperature($element, $element->{temp} - $temperatureOffset, 1);
	}
	return join(" / ", map($_->{element},  @heatingDayElements));
}

sub hhc_GetWeekDay($)
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

sub hhc_IsValidTemperature($)
{
    # TODO: There is a PERL warning thrown from this function.
    #       Use of uninitialized value $val in pattern match
    my ($val) = @_;
    return $val =~ /^[1-9][0-9](\.[05])?$/;
}

sub hhc_IsValidNumber
{
    my ($val) = @_;
    return $val =~ /^[1-9][0-9]*$/;
}

sub hhc_IsValidTime 
{ 
    my $s = shift; 
    if ($s =~ s/^([0-9]|0[0-9]|1[0-9]|2[0-3]):([0-5][0-9])$/sprintf('%02d:%02d',$1,$2)/e) { 
        return $s; 
    } else { 
        return undef; 
    } 
} 

sub hhc_IsValidHotWaterTemp 
{ 
    my $s = shift; 
    if ($s =~ s/^(ON|OFF|HEAT)$/\U$1/i) { 
        return $s; 
    } else { 
        return undef; 
    } 
}

sub hhc_AddOffestTemperature($$)
{
    my $temp = shift;
    my $tempOffsetOrName = shift;

    my $tempOffset = $tempOffsetOrName;
    if (!hhc_IsValidNumber($tempOffsetOrName)) {
        $tempOffset = AttrVal($tempOffsetOrName, 'temperatureOffset', 0);
    }    
    
    Log(5, "hhc_AddOffestTemperature: Enter - Temp - ${temp} tempOffset - ${tempOffset}");

    if (defined($tempOffset) && hhc_IsValidTemperature($temp)) {
        $temp = hhc_MakeValidTemperature($temp + $tempOffset);
    }

    Log(5, "hhc_AddOffestTemperature: Exit - return - ${temp}");

    return $temp;
}

sub hhc_SubOffestTemperature($$)
{
    my $temp = shift;
    my $tempOffsetOrName = shift;

    my $tempOffset = $tempOffsetOrName;
    if (!hhc_IsValidNumber($tempOffsetOrName)) {
        $tempOffset = AttrVal($tempOffsetOrName, 'temperatureOffset', 0);
    }

    Log(5, "hhc_SubOffestTemperature: Enter - Temp - ${temp} tempOffset - ${tempOffset}");

    if (defined($tempOffset) && hhc_IsValidTemperature($temp)) {
        $temp = hhc_MakeValidTemperature($temp - $tempOffset);
    }

    Log(5, "hhc_SubOffestTemperature: Exit - return - ${temp}");

    return $temp;
}

sub hhc_MakeValidTemperature($)
{
    my $temp = shift;

    Log(5, "hhc_MakeValidTemperature: Enter - Temp - ${temp}");

    if ($temp > hhc_MaxTemperature()) {
        $temp = hhc_MaxTemperature();
    } elsif ($temp < hhc_MinTemperature()) {
        $temp = hhc_MinTemperature();
    }
    Log(5, "hhc_MakeValidTemperature: Exit - Temp - ${temp}");
    return $temp;
}

sub hhc_MinTemperature()
{
    return 5;
}

sub hhc_MaxTemperature()
{
    return 32;
}

sub hhc_SerializeTemperature 
{
    # Print number in format "0.0", pass "on" and "off" verbatim, convert 30.5 and 4.5 to "on" and "off"
    # Used for "desiredTemperature", "ecoTemperature" etc. but not "temperature"

    my $t = shift;
#    return $t    if ( ($t eq 'on') || ($t eq 'off') );
#    return 'off' if ( $t ==  4.5 );
#    return 'on'  if ( $t == 30.5 );
    return sprintf('%2.1f', $t);
}

1;