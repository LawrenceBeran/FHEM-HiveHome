use strict;
use warnings;

use lib '.';
use AWSCognitoIdp;
use JSON;
use Data::Dumper;


my $credentials_filename = 'credentials.json';
my $username = 'XXXX';
my $password = 'XXXX';

my $deviceGroupKey  = undef;
my $deviceKey       = undef;
my $devicePassword  = undef;


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

    if (defined($credentials->{deviceGroupKey}))
    {
        $deviceGroupKey = $credentials->{deviceGroupKey};
        $deviceKey      = $credentials->{deviceKey};
        $devicePassword = $credentials->{devicePassword};
    }
}

#$deviceGroupKey = undef;
#$deviceKey      = undef;
#$devicePassword = undef;

my $awsAuth = AWSCognitoIdp->new(userName => $username, password => $password, deviceGroupKey => $deviceGroupKey, deviceKey => $deviceKey, devicePassword => $devicePassword);

if (defined($deviceGroupKey)) {
    
    my $loginResult = $awsAuth->loginDevice();


    my $refreshTokens = $awsAuth->refreshToken();

} else {


    my $loginResult = $awsAuth->loginSRP();
    if ($loginResult) {

        # If login requires 2FA
        if (uc($loginResult->{ChallengeName}) eq 'SMS_MFA') {

            # The code will be sent, probably via SMS...
            print("\n\nEnter the code?\n");
            my $code = <>;
            chomp($code);
            $loginResult = $awsAuth->loginSMS2FA($code, $loginResult->{Session});
        }

        my $authResult = $loginResult->{AuthenticationResult};
        if ($authResult) {

            my $confDevices = $awsAuth->confirmDevice($authResult);

            print(Dumper($authResult));
            print(Dumper($confDevices));

            ($deviceGroupKey, $deviceKey, $devicePassword) = $awsAuth->getDeviceData();

            $authResult->{RefreshToken};
            $authResult->{AccessToken};
            $authResult->{TokenType};                           # Bearer
            $authResult->{IdToken};
            $authResult->{ExpiresIn};                           # Number of seconds till token expires
            $authResult->{NewDeviceMetadata}->{DeviceKey};
            $authResult->{NewDeviceMetadata}->{DeviceGroupKey};

##            my $awsAuth2 = AWSCognitoIdp->new(userName => $username, password => $password, deviceGroupKey => $deviceGroupKey, deviceKey => $deviceKey, devicePassword => $devicePassword);
##            my $loginResult2 = $awsAuth->loginDevice();


#            my $refreshAuthResult = $awsAuth->refreshToken($authResult->{RefreshToken}, $authResult->{NewDeviceMetadata}->{DeviceKey});

#            if (!$refreshAuthResult) {
        
#            } else {
#                print(Dumper($refreshAuthResult));
#            }


        }
    }
}

sub Log3($$$)
{
    my ( $from, $loglevel, $text ) = @_;

    print('['.$from.']['.$loglevel.'] '.$text);
    # This subroutine mimics the interface of the FHEM defined Log so that the test does not crash.
}