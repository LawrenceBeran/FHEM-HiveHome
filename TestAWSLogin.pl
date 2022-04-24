use strict;
use warnings;

use lib '.';
use AWSCognitoIdp;
use JSON;
use Data::Dumper;
use REST::Client;

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


my $loginClient = REST::Client->new();



my $ua = LWP::UserAgent->new;
my $url = 'https://sso.hivehome.com/';


$loginClient->GET($url);
if (200 != $loginClient->responseCode()) {

} 

$loginClient->responseContent() =~ m/<script>(.*?)<\/script>/;
my $scriptData = '{"'.$1.'}';
$scriptData =~ s/,/,"/ig;
$scriptData =~ s/=/":/ig;
$scriptData =~ s/window.//ig;
print($scriptData);

my $data = decode_json($scriptData);

print(Dumper($data));

my ($region, $poolId) = (split('_', $data->{HiveSSOPoolId}))[0,1];
my $cliid = $data->{HiveSSOPublicCognitoClientId};


my $awsAuth = AWSCognitoIdp->new(userName => $username, password => $password, region => $region, 
                                poolId => $poolId, clientId => $cliid);
my $authResult = $awsAuth->loginSRP();


if ($authResult) {


    my $refreshAuthResult = $awsAuth->refreshToken($authResult->{RefreshToken}, $authResult->{NewDeviceMetadata}->{DeviceKey});

    if (!$refreshAuthResult) {

    } else {
        print(Dumper($refreshAuthResult));
    }

}



sub Log3($$$)
{
    my ( $from, $loglevel, $text ) = @_;

    print('['.$from.']['.$loglevel.'] '.$text);
    # This subroutine mimics the interface of the FHEM defined Log so that the test does not crash.
}