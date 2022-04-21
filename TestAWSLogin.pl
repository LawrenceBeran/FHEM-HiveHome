use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use HTTP::Request;
use JSON;
use HTML::Parser;
use Data::Dumper;
use POSIX qw(strftime);
use MIME::Base64;
use Encode qw(decode encode);

use Digest::SHA qw(sha256_hex hmac_sha256_hex hmac_sha256);
use Digest::HMAC;

#use bigint;
#use bigint qw/hex oct/;
use Math::BigInt;


my $username = '<username>';
my $password = '<password>';

# used - https://github.com/Pyhass/Pyhiveapi/blob/7d4cd7e63c3ec9f1a1c55a41e28be84f2aed4fa4/pyhiveapi/apyhiveapi/api/hive_auth.py

my $PASSWORD_VERIFIER_CHALLENGE = "PASSWORD_VERIFIER";

my $N_HEX = 'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'.
        '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'.
        'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'.
        'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'.
        'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D'.
        'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'.
        '83655D23DCA3AD961C62F356208552BB9ED529077096966D'.
        '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'.
        'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9'.
        'DE2BCBF6955817183995497CEA956AE515D2261898FA0510'.
        '15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64'.
        'ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7'.
        'ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6B'.
        'F12FFA06D98A0864D87602733EC86A64521F2B18177B200C'.
        'BBE117577A615D6C770988C0BAD946E208E24FA074E5AB31'.
        '43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF';

my $G_HEX = '2';
my $INFO_BITS = 'Caldera Derived Key';

# See - https://github.com/amazon-archives/amazon-cognito-auth-js/blob/v1.3.2/src/CognitoAuth.js#L759
# Function call getUserContextData (bottom of script)
# Call to AmazonCognitoAdvancedSecurityData
sub generateUserContextData($$$) {
    my $username = shift;
    my $userPoolId = shift;
    my $clientId = shift;

    my $timestamp = '1650094955414';
    # See this for details - https://en.wikipedia.org/wiki/Security_through_obscurity
    # It is constructed from 'username', 'userpoolId' and 'client id'
    # It is a base64 encoded JSON object
    #

    # {"payload":{"contextData":{"UserAgent":"Mozilla5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.88 Safari/537.36","DeviceId":"ft7ybs4ul023p02swu0f:1601851221518","DeviceLanguage":"en-GB","DeviceFingerprint":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.88 Safari/537.36PDF Viewer:Chrome PDF Viewer:Chromium PDF Viewer:Microsoft Edge PDF Viewer:WebKit built-in PDF:en-GB","DevicePlatform":"Win32","ClientTimezone":"01:00"},"username":"lawrence.beran@gmail.com","userPoolId":"eu-west-1_SamNfoWtf","timestamp":"1650094955414"},"signature":"EVz9vPKeSOLcbMQ9AWtDrUYyExrwg7snz2wwKjmOCDM=","version":"JS20171115"}

    my $payload = {
                contextData => {
                        UserAgent =>            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.88 Safari/537.36'
                    ,   DeviceId =>             'ft7ybs4ul023p02swu0f:1601851221518'
                    ,   DeviceLanguage =>       'en-GB'
                    ,   DeviceFingerprint =>    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.88 Safari/537.36PDF Viewer:Chrome PDF Viewer:Chromium PDF Viewer:Microsoft Edge PDF Viewer:WebKit built-in PDF:en-GB'
                    ,   DevicePlatform =>       'Win32'
                    ,   ClientTimezone =>       '01:00'
                }
            ,   username => $username 
            ,   userPoolId => $userPoolId
            ,   timestamp => $timestamp
        };

    my $signature = ''; # Base64 encoded signature of the payload object.
    my $version = 'JS20171115';

    my $userContextData = {
            payload => $payload
        ,   signature => $signature
        ,   version => $version
        };

}

sub generateRandom($) {
    my $sizeBytes = shift;

    my @set = ('0' ..'9', 'A' .. 'F');
    my $str = join '' => map $set[rand @set], 1 .. $sizeBytes*2;

    return Math::BigInt->from_hex($str);
}

sub padHex($) {
    my $hexValue = shift;

    if (length($hexValue) % 2 == 1) {
        $hexValue = '0'.$hexValue;
    } elsif (index('89ABCDEFabcdef', substr($hexValue, 0, 1)) != -1) {
        $hexValue = '00'.$hexValue;
    }
    return $hexValue;
}

sub hash_sha256($) {
    my $data = shift;

    my $temp = sha256_hex($data);
    my $hash = sprintf('%-*s', 64, $temp);
    return $hash;
}

sub hexHash($) {
    my $valueHex = shift;

    # Convert the value to binary.
    my $bytes = pack("H*", $valueHex);

    return hash_sha256($bytes);
}

#Calculate the client's value U which is the hash of A and B.
sub calculateU($$) {
    my $largeA = shift;
    my $serverB = shift;

    my $uHex = hexHash(padHex($largeA->to_hex()).padHex($serverB->to_hex()));
    return Math::BigInt->from_hex($uHex);
}


my $BIG_N = Math::BigInt->from_hex($N_HEX);
my $G = Math::BigInt->from_hex($G_HEX);
my $K = Math::BigInt->from_hex(hexHash('00'.$N_HEX.'0'.$G_HEX));

sub generateSmallA() {
    my $rnd = generateRandom(128);
    $rnd = Math::BigInt->new('114904749852874150273628708634582749044919403962151865244934285010698547700791149832387866823900365467026537191888308048799874366290794003128650060077194494730597227875928924102246052857515030111400777672253681955955944686047144996265348153531089337796426863174151635891118412829059735517767631010442501261030');
    return $rnd->bmod($BIG_N);
}

sub generateLargeA($$) {
    my $smallA = shift;
    my $gValue = shift;

    my $bigA = $gValue->copy()->bmodpow($smallA, $BIG_N);
    if ($bigA->bmod($BIG_N) == 0) {
        # Error...
        $bigA = undef;
    }
    return $bigA;
}

my $smallA = generateSmallA();
my $largeA = generateLargeA($smallA, $G);

sub computeHKDF($$) {
    my $ikmHex = shift;
    my $saltHex = shift;

    my $pk = hmac_sha256(pack("H*", $ikmHex), pack("H*", $saltHex));
    my $varInfoBits = $INFO_BITS.chr(1);
    my $hmac_hash = hmac_sha256($varInfoBits, $pk);

    return substr($hmac_hash, 0, 16);
}

sub getPasswordAuthenticationKey($$$$$$$) {
    my $poolId = shift;
    my $userId = shift;
    my $password = shift;
    my $srpB = shift;
    my $saltHex = shift;
    my $largeA = shift;
    my $gValue = shift;

    my $serverB = Math::BigInt->from_hex($srpB);
    my $uValue = calculateU($largeA, $serverB);
    # TODO: verify u - must not be 0.

    my $usernamePassword = $poolId.$userId.':'.$password;
    my $usernamePasswordHash = hash_sha256($usernamePassword);

    my $xValue = Math::BigInt->from_hex(hexHash(padHex($saltHex).$usernamePasswordHash));

    my $gModPowXN = $gValue->copy()->bmodpow($xValue, $BIG_N);
    my $intVal2 = $serverB->bsub($K->bmul($gModPowXN));
    my $sValue = $intVal2->bmodpow($smallA->badd($uValue->copy()->bmul($xValue)), $BIG_N);

    return computeHKDF(padHex($sValue->to_hex()), padHex($uValue->to_hex()));
}





 





# See the following for the authentication flow for - USER_SRP_AUTH
# https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-authentication-flow.html#Built-in-authentication-flow-and-challenges




my $ua = LWP::UserAgent->new;


my $url = 'https://sso.hivehome.com/';

my $resp = $ua->get($url);
if (!$resp->is_success) {
    print($resp->decoded_content);
    die $resp->status_line;
}

# Can test with
#   $resp->is_success

$resp->decoded_content =~ m/<script>(.*?)<\/script>/;

my $scriptData = '{"'.$1.'}';
$scriptData =~ s/,/,"/ig;
$scriptData =~ s/=/":/ig;
$scriptData =~ s/window.//ig;
#print($scriptData);

my $data = decode_json($scriptData);

print(Dumper($data));

my $upid = $data->{HiveSSOPoolId};
my $userPoolId = $data->{HiveSSOPoolId};
my ($region, $poolId) = (split('_', $data->{HiveSSOPoolId}))[0,1];
my $cliid = $data->{HiveSSOPublicCognitoClientId};

# Need to get my token from AWS Cognito Identiy Pool.



#
# Initiate authentication...
#



my $dataAuth = {
        AuthFlow => 'USER_SRP_AUTH'
    ,   ClientId => $cliid
    ,   AuthParameters => {
            SRP_A => $largeA->to_hex()
        ,   USERNAME => $username
        }
    };

my $advancedSecurity = undef;

if ($advancedSecurity) {
    my $userContextData = {
            EncodedData => generateUserContextData($username, $userPoolId, $cliid)
        };
    $dataAuth->{UserContextData} = $userContextData;
}

print(Dumper($dataAuth));

my $header = [  'X-Amz-Target' => 'AWSCognitoIdentityProviderService.InitiateAuth'
            ,   'Content-Type' => 'application/x-amz-json-1.1'];

# AWS URL is constructed something like:
#   https://cognito-idp.<region>.amazonaws.com/
# e.g., https://cognito-idp.<region>.amazonaws.com/
#
# See - https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html
my $urlInitAuth = 'https://sso.hivehome.com/auth/login?client=v3-web-prod';

my $requestInitAuth = HTTP::Request->new('POST', $urlInitAuth, $header, to_json($dataAuth));
my $respInitAuth = $ua->request($requestInitAuth);

if (!$respInitAuth->is_success) {
    print($respInitAuth->decoded_content);
    die $respInitAuth->status_line;
}

my $dataInitAuth = decode_json($respInitAuth->decoded_content);
#my $dataInitAuth = decode_json('{"ChallengeName": "PASSWORD_VERIFIER", "ChallengeParameters": {"SALT": "7c4f076023e6b785d153cbe9d5aced63", "SECRET_BLOCK": "VC4h8TQIR79gYlqVaHgJ4wJv5JbVVgIN/BorHusSC6zqigSsSDs3G3Sm+IokMx25RB/NozqN5uxs2aNi4KhqcUd7cu90tJoh9jbcFbj3zHBa+0/TbEIU5yK8n7fhMAEywKnPrkCS1UvmXq0ce1pxzsX8Dpi9Wjjmv/BICLUnQDkfOIgq4uX4FtqMWsYhz8VRpjEP5qW9GNnInk76/iKbDGvyhrrRK1LVoDliH+GjIXplQvm4h0N4Z/I/XlHjeMWkWQufcEs4a6H1kbr4eFGcbpYVbd6eGj9tbFcEgUAIBhy9efS3XihgvYLyA98Z1eaarhXHFJ82P4BOz+quOQvWtPyQMEAoxzbUjFSzIwaRpPRQC9rTp45Ktf1l45As4eE0BKtHUtANPzv28ADPMBo4EF49yzEJWj3xouGSPYEBWw+ULVJlWck9NwXumtQRdMPxMRMXDUrwcLH2jHho0QavIDkDrJKc5Np6SpmlbIjqnKcMIozL3h9EXI1TaCrin0KSQC6BwrOGvGhkrFgrxZF/4iji/A9SupeehYKUqHtyxorez4LW/BUte3SyqMXEfRuS8rawvpb2iY9oaYJeR8lMrh142yX0qBVS4ZHwmpTHDz1WmtL/kyAk3lqiR8u3yy3jF460gaW4LamuiJC5rcKYjAKRsTIMCXdlzGERn14kkmPwV9IwiDLyfYvVaklBPM3tlLevCQv8gnGMVRgF2oJyAI3yWD1EHfm184IMV6m1pUgj5ndevNud1NyZ/qYArVCfH8NXsM9o3CYEHxzesRve/LWjyJcrr9YT1+1NhNoedNlqFhkSNKQSFW0AubTbVXUpIM0pP9QmYJDN90Q1fDHS1VpLxVKihdo5V/C3I9PFyTVjLK4JabIMJq8NxWUh2Os5gug/56RRSHRUNRPRdS1B3lGxwCyARdXbVEo6klB7rFC8dMMjOt0BTKH+fB/aATHCjpK3DEQ9uAGkFwOPBSIZ+T1lHy/ImcIMRyTiv+M8ELasgMme05CLFo6It0mor+d53ulizzmCTJdT7ePngDlzS3VjMDohs97sqXdgoag5ye0d5R6skEcaFZfTmDOhvPNmcR0m4+GDCI6t967eT2tgO/bxQaS8GWGo/K+z/uKEKdmYARs5aGd5b93xbbmakhxpbrnseOrKpkgvayRXfCd66TjqtRUvm0tV6DQtVt067pq14+EL5MfyAzy+rPythrv42pF4XxMc6wCXSFe6CpUAwtL0cQtW6JmLXh+r291SjhcI6/N2klTuKHSqjIk39G6FK21t+tbgB9VkXk71Cf5cjKi86Qm0ibIvhwLyoUsRrrSnMgWFZYA5id/3mGeCksIvT0Z4KwH2E0sBlPeGJx85/YUmyRhtP+SuQPm+kRwWgb3KbM+jAT/HUugOeyoygJkytQxFzSJgAO+ZidSmm0nuIvgmtDZbPyFnO23DfBlekqDNic2jmVTQFc/O8X/2w18Brf7fYEDlUGbxUJmn+sszSydK7tgX/5tuZWzQuSzyuaR8eQ2VU/nCg745ep2dMC339OgAbHD9IztciZRYQI478/RJlw9LLMxs+a9620Rjw/o+HmQ02ZM/MsEJbKPKe9KH6XGuS+O2IKOrZl9FNXGP6wTr79VbZnbBNzoOFG8TP/kXtl+9xULdGEDsi/RoB2mWxFoijrfrbw6W6giGbrLtgmtR5b7LFltnipQ58kRMj2S+CMimYsoDxzBrwkc=", "SRP_B": "878fa6955768be1cc6c62360e18e16e9af82daa57d232a3b56c9b4a48e8de1d0dab288ee3b1404dde59c53268e0f3909148938c1a5aefe90271e492d294a8229ec8d5d0e84d1ba710bc50d880e92a3a23d778e5abcbca462818c2e95c6b2059ab2dca76e0ba91cca83dfc0e70e424986985cf6d37d9f38dd3fc03f6cdf0cc0ba5ed33a7f3319c2c2ef91a064b97106403788118f77552be98c1ea18ae3280390358bc1568a7b9965bfe3655ed78695e6a9d7c678a701b74bdf83ed7b675694ecb5a6bdb431dd947a65ac7353575361fb46117171be2bcc3f958f252a0cc1e00c1813cee844dbb3dd3c0b02faaed623d3c490bc7a4a7d686c23017a4e28c5e1d1e5b35ad6419e5eb9f8eefdd338c6986751bb90970e5a36541b07284deaa293db3617b7b7895beeb7e5edd7cf78ae6243f86db6fb2ca83923213b71faa7c7262b7b6bcb0a24768bbf8dec68b37badbe50dcc2ec8dcf599a72166e5117ba7df78bbfc9390600823dda1e306438613f115456d74f42afa857b17027f6adbf28551f", "USERNAME": "a68c740a-8385-42d7-b8fb-ea5496094942", "USER_ID_FOR_SRP": "a68c740a-8385-42d7-b8fb-ea5496094942"}}');

if ($dataInitAuth->{ChallengeName} ne $PASSWORD_VERIFIER_CHALLENGE) {
    print('The '.$dataInitAuth->{ChallengeName}.' challenge is not supported!');
    die('The '.$dataInitAuth->{ChallengeName}.' challenge is not supported!');
}
print(Dumper($dataInitAuth));


my $challangeParameters = $dataInitAuth->{ChallengeParameters};

#my $userID = $challangeParameters->{USERNAME};
my $userID = $challangeParameters->{USER_ID_FOR_SRP};
my $saltHex = $challangeParameters->{SALT};
my $srpBHex = $challangeParameters->{SRP_B};
my $secretBlockB64 = $challangeParameters->{SECRET_BLOCK};
my $secretBlock = decode_base64($secretBlockB64);


#
# Challenge response
#


# {
#   "ChallengeName":"PASSWORD_VERIFIER",
#    "ChallengeParameters":{
#       "SALT":"7c4f076023e6b785d153cbe9d5aced63",
#       "SECRET_BLOCK":"czMBJnI4X++KbONM2WQ2yyNAE51RqU21KMw8n9GP/DcgiGisI0ag7QCkigzLGIaglTD1sJjSWDQAq/D7tLbA4cEsIhWKtuxh3p0AKIc2NJC0JDWZ59NErVLrbLeGF0Fd36pVSbpNL6oiwSRgOMvLWHzY6e4CT/YYBMdFyhfXMb8/36jjXDjBahoOvp1jkZSZmm9dIBWRbHkvdFmUWRTkdDpeA0RR0HHZo7ofghAwD0MN4v/wNkU8ffnMgsMpt3Hw/wKGqjuucjiMBAyB6pJQge18livB/E1yNLP0tWI/OW/WSdAe/munMWOG/oAN9f3/nak01eR7F2fjRgrdj0turtjTK/1XPUk33Nyg/2SwMNznIPJF+S51UbWUsJS61d+M44NJQzGPdMg06HVrQk5HHf8E7wI3pBpDL3eyIM2TpKtug7tb+Q8y/f6HlMYwlUWJ+xxSx0xhjjpzXU/vpByoACSTDHREkT69b8uTsWfkG7F184jafeHXJ0MomG0ZnLvpELNx4dj3LcSk7xkvJ3WeuLoFvcNz0llGe+gupJALV/p0+d3CifIr8TeJmB7e9wcvjOi2NCKEkTBV2iGJH08eRQJAosuBYYD3uJZMQQe/ewanNAgOjzdvKVnXDJgPDadYvDuaTJabr470vT7FOKI4lbDE5/hKZxI28zYw2zJAGcj8MK/+C08qqPvPO6U+NymSEYYJK+cxP5wF3/xjV2dXW/6mmRh196G4bWFC2UGb5MufeFPe2L6LcYHyJER+mLq3N12UC5sqODDgdxvk8zitYjSrLF68FcWW9Ij2+Kja95Ramq+UhHe3I2pLirHykgfiatN5dunf2Mlbv2On6B5TheqYPATiUvuf/QG0nifCabt66dlarj5DLQ1a5g8CwQ5g5qP1",
#       "SRP_B":"ff2dd405507b85ad2052beaeb515820c18bf930a1af3d8ec42b7e576f02abd5733b0723daeb467eec73122cae3520d8bb6111259fd3bd6d1536e47db86ba72913b75c99bbaa322bf018f73162fa7d418b637a43e94455668834947bf54a344d6c50ad29eae6b321a430a0459066523c096877da3dfbdf236f941cd82f0ac47fba5ec37707dc5f0a165caa810cc335f151765fbe551dc0e2e2bc8bfc818fe656d7a81407552112c168300bf0f1bb217f76b45a13ae3bdcc73f72214e8a0daf87de689287c55e8730c681d602fc6c3da8e4aeb87e4ee65916e1393778385235b9005a44882e70ec53689025c672fe46655e4e750e923960756e980456ecce5b608a0702878ca5ae2134d8596158faee93aa92b23d19d69aac9b1ec8fa8e9510fb48bd354127eb06984cc5190950833f12fe8e4b6d1dfa65fa5807f0188fa70ecce09e4de8a639ae26458c5f925791d26c7b0260782d386c00a7982630a663226ebfb78fa3836e576c895e2d3b720d7171bdf0b1d5416b91907f349da25c030bb7b",
#       "USERNAME":"a68c740a-8385-42d7-b8fb-ea5496094942",
#       "USER_ID_FOR_SRP":"a68c740a-8385-42d7-b8fb-ea5496094942"
#   }
# }



my $timeStamp = strftime("%a %b %d %H:%M:%S UTC %Y", localtime());
$timeStamp =~ s/ 0(\d) / $1 /ig;

my $hkdf = getPasswordAuthenticationKey($poolId, $userID, $password, $srpBHex, $saltHex, $largeA, $G);
my $msg = $poolId.$userID.$secretBlock.$timeStamp;
my $signature = encode_base64(hmac_sha256($msg, $hkdf));
chomp($signature);





# Python HiveHome implementation - https://github.com/Pyhass/Pyhiveapi/blob/master/pyhiveapi/apyhiveapi/api/hive_auth.py
# Check out this PHP implementation - https://gist.github.com/jenky/a4465f73adf90206b3e98c3d36a3be4f
# and this Java implementation - https://github.com/aws-samples/aws-cognito-java-desktop-app/blob/master/src/main/java/com/amazonaws/sample/cognitoui/AuthenticationHelper.java




my $dataChallangeResponse = {
        ChallengeResponses => {
            USERNAME => $userID
        ,   PASSWORD_CLAIM_SECRET_BLOCK => $secretBlockB64
        ,   TIMESTAMP => $timeStamp
        ,   PASSWORD_CLAIM_SIGNATURE => $signature
        }
    ,   ChallengeName => $PASSWORD_VERIFIER_CHALLENGE
    ,   ClientId => $cliid 
    };

if ($advancedSecurity) {
    my $userContextData = {
        EncodedData => generateUserContextData($username, $userPoolId, $cliid)
    };
    $dataChallangeResponse->{UserContextData} = $userContextData;
}


print(Dumper($dataChallangeResponse));

my $requestChallengeResponse = HTTP::Request->new('POST', $urlInitAuth, $header, to_json($dataChallangeResponse));
my $respChallengeResponse = $ua->request($requestChallengeResponse);

if (!$respChallengeResponse->is_success) {
    print($respChallengeResponse->decoded_content);
    die $respChallengeResponse->status_line;
}
print($respChallengeResponse->decoded_content);

my $dataChallengeResponse = decode_json($respChallengeResponse->decoded_content);

