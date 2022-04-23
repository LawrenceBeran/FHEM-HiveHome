use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;
use AWSCognitoIdp;

use JSON;
use Data::Dumper;

my $username = '<username>';
my $password = '<password>';


my $ua = LWP::UserAgent->new;
my $url = 'https://sso.hivehome.com/';

my $resp = $ua->get($url);
if (!$resp->is_success) {
    print($resp->decoded_content);
    die $resp->status_line;
}

$resp->decoded_content =~ m/<script>(.*?)<\/script>/;

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