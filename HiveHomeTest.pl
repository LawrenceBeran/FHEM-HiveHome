#
use strict;
use warnings;
use utf8;

use lib '.';
use HiveHomeInterface;
use Data::Dumper;
use JSON;
use List::Util qw(first);


my $credentials_filename = 'credentials.json';
my $username = 'XXXX';
my $password = 'XXXX';

### Load credentials from file
my $credentialsString = do {
    open(my $fhIn, "<", $credentials_filename);
    local $/;
    <$fhIn>
};

if (defined($credentialsString))
{
    my $credentials = decode_json($credentialsString);
    $username = $credentials->{username};
    $password = $credentials->{password};
}

my $token_filename = 'HiveHome-token.json';
my $token = undef;
my $refreshToken = undef;
my $accessToken = undef;
my $deviceKey = undef;

### Load the previous token from file
my $tokenString = do {
    open(my $fhIn, "<", $token_filename);
    local $/;
    <$fhIn>
};

if (defined($tokenString))
{
    my $tokens = decode_json($tokenString);
    $token = $tokens->{token};
    $refreshToken = $tokens->{refreshToken};
    $accessToken = $tokens->{accessToken};
    $deviceKey = $tokens->{deviceKey};
}

### Connect to the HiveHomeAPI
my $hiveHomeClient = HiveHomeInterface->new(userName => $username, password => $password, token => $token,
                                        refreshToken => $refreshToken, accessToken => $accessToken, deviceKey => $deviceKey);



my $tests = {
        actions => undef
    ,   holidayMode => undef 
    ,   heatingBoost => undef
    ,   waterBoost => undef
    ,   trvBoost => undef
    ,   heatingMode => undef
    ,   waterMode => undef
    ,   trvMode => undef
    ,   heatingSchedule => undef
    ,   waterSchedule => undef
    ,   trvSchedule => undef
};

################################################################################################################
# Test getting devices and products calls.

my @devices = $hiveHomeClient->getDevices();
### Save the devices
#open(my $fhOutDevices, ">", "devices.json");
#print($fhOutDevices encode_json(\@devices));
#close($fhOutDevices);  


my @products = $hiveHomeClient->getProducts();
### Save the products
#open(my $fhOutProducts, ">", "products.json");
#print($fhOutProducts encode_json(\@products));
#close($fhOutProducts);  

# Get found products that can be tested (currently only supports single zone and single trvcontrol)
my ($heatingItem) = first { 'heating' eq lc($_->{type}) } @products;
my ($hotWaterItem) = first { 'hotwater' eq lc($_->{type}) } @products;
my ($trvItem) = first { 'trvcontrol' eq lc($_->{type}) } @products;


################################################################################################################
# Test action calls.

if (defined($tests->{actions}))
{
    my @actions = $hiveHomeClient->getActions();
    print("Actions".Dumper(@actions));


    #if (defined($action))
    #{
        # Activate the boot heating for 30 mins
    #    my $ret = $hiveHomeClient->activateAction('<id>');
    #    my $ret = $hiveHomeClient->activateAction($action->{id});
    #}
}

################################################################################################################
# Test holiday mode calls.

if (defined($tests->{holidayMode}))
{
    PrintCurrentHolidayMode($hiveHomeClient);

    # Set the holiday start date for a week in the future and to end a week after.
    my $weekInSeconds = 86400 * 7;
    my $startTime = time + $weekInSeconds;
    my $endTime = $startTime + $weekInSeconds;

    my $holidayMode = $hiveHomeClient->setHolidayMode($startTime, $endTime, 7);
    print("Setting holiday mode: ".Dumper($holidayMode)."\n");

    PrintCurrentHolidayMode($hiveHomeClient);

    $holidayMode = $hiveHomeClient->cancelHolidayMode();
    print("Cancel holiday mode: ".Dumper($holidayMode)."\n");
    if (defined($holidayMode))
    {
        if ($holidayMode->{set})
        {
            print("   Holiday mode cancelled!\n");
        }
        else
        {
            print("   Holiday mode not cancelled!\n");
        }
    }

    PrintCurrentHolidayMode($hiveHomeClient);
}

################################################################################################################
# Test heating boost calls.

if (defined($tests->{heatingBoost}))
{
    if (defined($heatingItem))
    {
        my $boostMode = $hiveHomeClient->setHeatingBoostMode($heatingItem->{id}, 21.4, 30);
        print("Heating boost mode: ".Dumper($boostMode)."\n");

        # Get the products to see if the boost details are provided.
        my @products = $hiveHomeClient->getProducts();
        print("Products: ".Dumper(@products)."\n");

        my $boostMode = $hiveHomeClient->cancelHeatingBoostMode($heatingItem->{id});
        print("Heating boost mode: ".Dumper($boostMode)."\n");
    }
}

################################################################################################################
# Test hot water boost calls.

if (defined($tests->{waterBoost}))
{
    if (defined($hotWaterItem))
    {
        my $boostMode = $hiveHomeClient->setHotWaterBoostMode($hotWaterItem->{id}, 30);
        print("HotWater boost mode: ".Dumper($boostMode)."\n");

        # Get the products to see if the boost details are provided.
        my @products = $hiveHomeClient->getProducts();
        print("Products: ".Dumper(@products)."\n");

        my $boostMode = $hiveHomeClient->cancelHotWaterBoostMode($hotWaterItem->{id});
        print("HotWater boost mode: ".Dumper($boostMode)."\n");
    }
}

################################################################################################################
# Test trv boost calls.

if (defined($tests->{trvBoost}))
{
    if (defined($trvItem))
    {
        my $boostMode = $hiveHomeClient->setTRVControlBoostMode($trvItem->{id}, 21.4, 30);
        print("TRVControl boost mode: ".Dumper($boostMode)."\n");

        # Get the products to see if the boost details are provided.
        my @products = $hiveHomeClient->getProducts();
        print("Products: ".Dumper(@products)."\n");

        my $boostMode = $hiveHomeClient->cancelTRVControlBoostMode($trvItem->{id});
        print("TRVControl boost mode: ".Dumper($boostMode)."\n");
    }
}

################################################################################################################
# Test set heating Heating Mode calls.

if (defined($tests->{heatingMode}))
{
    if (defined($heatingItem))
    {
        my $heatingMode = $hiveHomeClient->setHeatingMode($heatingItem->{id}, 'OFF');
        print("Heating mode: ".Dumper($heatingMode)."\n");

        my $heatingMode = $hiveHomeClient->setHeatingMode($heatingItem->{id}, 'MANUAL', 7);
        print("Heating mode: ".Dumper($heatingMode)."\n");

        my $heatingMode = $hiveHomeClient->setHeatingMode($heatingItem->{id}, 'FRWD', 2);
        print("Heating mode: ".Dumper($heatingMode)."\n");

        my $heatingMode = $hiveHomeClient->setHeatingMode($heatingItem->{id}, 'SCHEDULE');
        print("Heating mode: ".Dumper($heatingMode)."\n");
    }
}

################################################################################################################
# Test set hot water Heating Mode calls.

if (defined($tests->{waterMode}))
{
    if (defined($hotWaterItem))
    {
        my $hotWaterMode = $hiveHomeClient->setHotWaterMode($hotWaterItem->{id}, 'OFF');
        print("HotWater mode: ".Dumper($hotWaterMode)."\n");

        my $hotWaterMode = $hiveHomeClient->setHotWaterMode($hotWaterItem->{id}, 'MANUAL', 7);
        print("HotWater mode: ".Dumper($hotWaterMode)."\n");

        my $hotWaterMode = $hiveHomeClient->setHotWaterMode($hotWaterItem->{id}, 'FRWD', 2);
        print("HotWater mode: ".Dumper($hotWaterMode)."\n");

        my $hotWaterMode = $hiveHomeClient->setHotWaterMode($hotWaterItem->{id}, 'SCHEDULE');
        print("HotWater mode: ".Dumper($hotWaterMode)."\n");
    }
}

################################################################################################################
# Test set trv Heating Mode calls.

if (defined($tests->{trvMode}))
{
    if (defined($trvItem))
    {
        my $heatingMode = $hiveHomeClient->setTRVControlMode($trvItem->{id}, 'OFF');
        print("TRV Control mode: ".Dumper($heatingMode)."\n");

        my $heatingMode = $hiveHomeClient->setTRVControlMode($trvItem->{id}, 'MANUAL', 7);
        print("TRV Control mode: ".Dumper($heatingMode)."\n");

        my $heatingMode = $hiveHomeClient->setTRVControlMode($trvItem->{id}, 'FRWD', 2);
        print("TRV Control mode: ".Dumper($heatingMode)."\n");

        my $heatingMode = $hiveHomeClient->setTRVControlMode($trvItem->{id}, 'SCHEDULE');
        print("TRV Control mode: ".Dumper($heatingMode)."\n");
    }
}

################################################################################################################
# Test setting heating schedule.

if (defined($tests->{heatingSchedule}))
{
    if (defined($heatingItem))
    {
        # [<weekday> <temp>,<until>,<temp>,<until>,<temp>,<until>] [<repeat>]
        # E.g. Wed 5.0,23:55,5.0
        # Note: MUST provide schedule for every day of the week otherwise it breaks Hive...
        my $heatingSchedule =   'mon 5,23:55,5 '.
                                'tue 5,23:55,5 '.
                                'wed 5,23:55,5 '.
                                'thu 5,23:55,5 '.
                                'fri 5,23:55,5 '.
                                'sat 5,23:55,5 '.
                                'sun 5,23:55,5';
        #my $heatingSchedule = 'mon 5,23:55,5';

        my $heatingMode = $hiveHomeClient->setHeatingSchedule($heatingItem->{id}, $heatingSchedule);
        print("Heating mode: ".Dumper($heatingMode)."\n");
    }
}

################################################################################################################
# Test setting hot water schedule.

if (defined($tests->{waterSchedule}))
{
    if (defined($hotWaterItem))
    {
        # [<weekday> <state>,<until>,<state>,<until>,<state>,<until>] [<repeat>]
        #E.g. Wed off,06:30,on,07:15,off,16:00,on,21:30,off
        my $heatingSchedule =   'mon off,06:30,on,07:15,off,16:00,on,21:51,off '.
                                'tue off,06:30,on,07:15,off,16:00,on,21:30,off '.
                                'wed off,06:30,on,07:15,off,16:00,on,21:30,off '.
                                'thu off,06:30,on,07:15,off,16:00,on,21:30,off '.
                                'fri off,06:30,on,07:15,off,16:00,on,21:30,off '.
                                'sat off,06:30,on,07:15,off,16:00,on,21:30,off '.
                                'sun off,06:30,on,07:15,off,16:00,on,21:30,off';

        my $heatingMode = $hiveHomeClient->setHotWaterSchedule($hotWaterItem->{id}, $heatingSchedule);
        print("Heating mode: ".Dumper($heatingMode)."\n");        
    }
}

################################################################################################################
# Test setting trv schedule.

if (defined($tests->{trvSchedule}))
{
    if (defined($trvItem))
    {
        # [<weekday> <temp>,<until>,<temp>,<until>,<temp>,<until>] [<repeat>]
        # E.g. Wed 5.0,23:55,5.0
        # Note: MUST provide schedule for every day of the week otherwise it breaks Hive...
        my $heatingSchedule = 'mon 5,23:55,5 tue 5,23:55,5 wed 5,23:55,5 thu 5,23:55,5 fri 5,23:55,5 sat 5,23:55,5 sun 5,23:55,5';
        #my $heatingSchedule = 'mon 5,23:55,5';

        my $heatingMode = $hiveHomeClient->setTRVControlSchedule($trvItem->{id}, $heatingSchedule);
        print("Heating mode: ".Dumper($heatingMode)."\n");
    }
}

################################################################################################################

### Get the latest used token
$token = $hiveHomeClient->getToken();
### Save the previous token to file
open(my $fhOut, ">", $token_filename);
print($fhOut encode_json($token));
close($fhOut);  






sub PrintCurrentHolidayMode {
    my $hiveHomeClient = shift;

    my $holidayMode = $hiveHomeClient->getHolidayMode();
    print("Holiday mode: ".Dumper($holidayMode));
    if (defined($holidayMode))
    {
        if ($holidayMode->{enabled})
        {
            print("  Holiday mode set!\n");
        }
        else
        {
            print("  Holiday mode not set!\n");
        }
    } 
    print("\n");
}

sub Log3
{
    my ( $self, $loglevel, $text ) = @_;

    print($text);
    # This subroutine mimics the interface of the FHEM defined Log so that the test does not crash.
    my $var = '';
}