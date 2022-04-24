package AWSCognitoIdp;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use JSON;
use Data::Dumper;
use POSIX qw(strftime);
use MIME::Base64;
use Digest::SHA qw(sha256_hex hmac_sha256_hex hmac_sha256);
use Math::BigInt lib => 'GMP';
use Carp qw(croak);


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



sub new        # constructor, this method makes an object that belongs to class Number
{
    my $class = shift;          # $_[0] contains the class name


    croak "Illegal parameter list has incorrect number of values" if @_ % 5;

    my %params = @_;

    my $self = {};              # the internal structure we'll use to represent
                                # the data in our class is a hash reference
    bless( $self, $class );     # make $self an object of class $class

    # This could be abstracted out into a method call if you 
    # expect to need to override this check.
    for my $required (qw{ userName password region poolId clientId }) {
        croak "Required parameter '$required' not passed to '$class' constructor"
            unless exists $params{$required};  
    }

    # initialise class members, these can be overriden by class initialiser.
    $self->{userName}   = undef;
    $self->{password}   = undef;
    $self->{region}     = undef;
    $self->{poolId}     = undef;
    $self->{clientId}   = undef;
    $self->{clientSecret} = undef;

    # TODO: Either pass userPoolId (a single parameter container poolId and region, or pass them seperatly)

    # initialize all attributes by passing arguments to accessor methods.
    for my $attrib ( keys %params ) {

        croak "Invalid parameter '$attrib' passed to '$class' constructor"
            unless $self->can( $attrib );

        $self->$attrib( $params{$attrib} );
    }

    # Provide a value to the following to log all successfull API calls and responses at the log level defined in - $self->{infoLogLevel}
    # Set it to undef to not log all responses, errors are still logged
    $self->{logAPIResponsesLevel} = 5;
    $self->{infoLogLevel} = 4;
    $self->{useAdvancedSecurity} = undef;

    $self->{ua} = LWP::UserAgent->new;




    return $self;        # a constructor always returns an blessed() object
}

sub DESTROY($)
{
    my $self = shift;
    $self->_log(5, "DESTROY - Enter");
}

# Attribute accessor method.
sub userName($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{userName} = $value;
    }
    return $self->{userName};
}

# Attribute accessor method.
sub password($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{password} = $value;
    }
    return $self->{password};
}

# Attribute accessor method.
sub region($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{region} = $value;
    }
    return $self->{region};
}
# Attribute accessor method.
sub poolId($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{poolId} = $value;
    }
    return $self->{poolId};
}
# Attribute accessor method.
sub clientId($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{clientId} = $value;
    }
    return $self->{clientId};
}
# Attribute accessor method.
sub clientSecret($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{clientSecret} = $value;
    }
    return $self->{clientSecret};
}

#############################
# Public methods
#############################

# TODO: Make this call a bit more generic, currently it is specific to the SRP AUTH process.
sub initAuthentication($$) {
    my ($self, $dataAuth) = @_;

    #
    # Initiate authentication...
    #   - https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html
    #

    $dataAuth = $self->_addUserContextData($dataAuth);

    my $dataAuthResponse = $self->_postData($dataAuth, $self->_getHeaders('InitiateAuth'));

    return $dataAuthResponse;
}

sub challengeResponse($$) {
    my ($self, $dataChallengeResponse) = @_;

    $dataChallengeResponse = $self->_addUserContextData($dataChallengeResponse);

    my $dataChallengeResponseResponse = $self->_postData($dataChallengeResponse, $self->_getHeaders('RespondToAuthChallenge'));

    return $dataChallengeResponseResponse->{AuthenticationResult};
}

sub confirmDevice($$) {
    my ($self, $respChallengeResponse) = @_;

    if ($respChallengeResponse->{NewDeviceMetadata}->{DeviceKey}) {

        # See - https://aws.amazon.com/premiumsupport/knowledge-center/cognito-user-pool-remembered-devices/
        #       https://stackoverflow.com/questions/52499526/device-password-verifier-challenge-response-in-amazon-cognito-using-boto3-and-wa
        # For details on how to make this call.

        my $randomPassword = encode_base64($self->generateRandom(40));
        my $fullPassword = $respChallengeResponse->{NewDeviceMetadata}->{DeviceGroupKey}.$respChallengeResponse->{NewDeviceMetadata}->{DeviceKey}.':'.$randomPassword;
        my $fullPasswordHash = Math::BigInt->from_bytes($self->hash_sha256($fullPassword));
        my $salt = $self->generateRandom(16);

        my $sum = $self->bigIntHash($salt->copy()->badd($fullPasswordHash));

        my $paswordVerifierB64 = encode_base64($self->padHex($self->{G}->copy()->bmodpow($sum, $self->{BIG_N})->to_hex()));
        chomp($paswordVerifierB64);
        my $saltB64 = encode_base64($salt);
        chomp($saltB64);

        my $dataConfirmDevice = {
                AccessToken => $respChallengeResponse->{AccessToken}
            ,   DeviceKey => $respChallengeResponse->{NewDeviceMetadata}->{DeviceKey}
            ,   DeviceName => 'User Agent'
            ,   DeviceSecretVerifierConfig => { 
                    PasswordVerifier => $paswordVerifierB64
                ,   Salt => $saltB64
               }
            } ;

        my $respConfirmDeviceResponse = $self->_postData($dataConfirmDevice, $self->_getHeaders('ConfirmDevice'));

        # TODO: Not sure if this response means I need to do anything else, but I can now
        #       refresh the clients tokens so probs nothing more is required.
        if ($respConfirmDeviceResponse->{UserConfirmationNecessary}) {

            # Need to provide response!
            my $val = '';
        }
    }
}

sub loginSRP($) {
    my ($self) = @_;

    # Prepare SRP details for authentication.

    $self->{BIG_N}  = Math::BigInt->from_hex($N_HEX);
    $self->{G}      = Math::BigInt->from_hex($G_HEX);
    $self->{K}      = Math::BigInt->from_hex($self->hexHash('00'.$N_HEX.'0'.$G_HEX));

    $self->{smallA} = $self->generateSmallA();
    $self->{largeA} = $self->generateLargeA();


    # See for the call order if devices are required to be used for refresh tokens.
    # https://aws.amazon.com/premiumsupport/knowledge-center/cognito-user-pool-remembered-devices/

    my $dataAuth = {
            AuthFlow => 'USER_SRP_AUTH'
        ,   ClientId => $self->{clientId}
        ,   AuthParameters => {
                SRP_A => $self->{largeA}->to_hex()
            ,   USERNAME => $self->{userName}
            }
        };

    my $dataInitAuth = $self->initAuthentication($dataAuth);

    if (!$dataInitAuth) {
        $self->_log(1, 'Error in call to initAuthentication!');
        return undef;
    }

    if ($dataInitAuth->{ChallengeName} ne $PASSWORD_VERIFIER_CHALLENGE) {
        $self->_log(1, 'The '.$dataInitAuth->{ChallengeName}.' challenge is not supported!');
        return undef;
    }

    #
    # Build challenge response
    #   - https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_RespondToAuthChallenge.html
    #

    my $challangeParameters = $dataInitAuth->{ChallengeParameters};

    my $userID = $challangeParameters->{USER_ID_FOR_SRP};
    my $saltHex = $challangeParameters->{SALT};
    my $srpBHex = $challangeParameters->{SRP_B};
    my $secretBlockB64 = $challangeParameters->{SECRET_BLOCK};
    my $secretBlock = decode_base64($secretBlockB64);

    my $timeStamp = strftime("%a %b %d %H:%M:%S UTC %Y", localtime());
    $timeStamp =~ s/ 0(\d) / $1 /ig;

    my $hkdf = $self->getPasswordAuthenticationKey($userID, $srpBHex, $saltHex);
    my $msg = $self->{poolId}.$userID.$secretBlock.$timeStamp;
    my $signature = encode_base64(hmac_sha256($msg, $hkdf));
    chomp($signature);

    my $dataChallengeResponse = {
            ChallengeResponses => {
                USERNAME => $userID
            ,   PASSWORD_CLAIM_SECRET_BLOCK => $secretBlockB64
            ,   TIMESTAMP => $timeStamp
            ,   PASSWORD_CLAIM_SIGNATURE => $signature
            }
        ,   ChallengeName => $PASSWORD_VERIFIER_CHALLENGE
        ,   ClientId => $self->{clientId}
        };

    my $respChallengeResponse = $self->challengeResponse($dataChallengeResponse);

    if (!$respChallengeResponse) {
        $self->_log(1, 'Error in call to challengeResponse!');
        return undef;
    }

    $self->confirmDevice($respChallengeResponse);

    return $respChallengeResponse;
}

# Note: May not return a new RefreshToken.
sub refreshToken() {
    my ($self, $refreshToken, $deviceKey) = @_;

    #
    # Initiate authentication...
    #   - https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html
    #

    my $refreshTokenAuth = {
            AuthFlow => 'REFRESH_TOKEN_AUTH'
        ,   ClientId => $self->{clientId}
        ,   AuthParameters => {
                    REFRESH_TOKEN => $refreshToken
                ,   DEVICE_KEY => $deviceKey
            }
        };

    my $refreshTokenAuthResp = $self->initAuthentication($refreshTokenAuth);

    if (!$refreshTokenAuthResp) {
        return undef;
    }

    return $refreshTokenAuthResp->{AuthenticationResult};
}


#############################
#   Internal helper methods
#############################

sub _postData($$$) {
    my ($self, $postData, $headers) = @_;

    $self->_log($self->{logAPIResponsesLevel}, Dumper($postData));

    my $requestPostData = HTTP::Request->new('POST', $self->_getAWSURL(), $headers, to_json($postData));
    my $respPostData = $self->{ua}->request($requestPostData);

    if (!$respPostData->is_success) {
        $self->_log(1, $respPostData->decoded_content);
        return undef;
    }

    my $respPostDataJSON = decode_json($respPostData->decoded_content);
    $self->_log($self->{logAPIResponsesLevel}, Dumper($respPostDataJSON));

    return $respPostDataJSON
}

sub _addUserContextData($$) {
    my ($self, $package) = @_;
    if ($self->{useAdvancedSecurity}) {
        my $userContextData = {
            EncodedData => $self->generateUserContextData()
        };
        $package->{UserContextData} = $userContextData;
    }
    return $package;
}

sub _getAWSURL($) {
    my ($self) = @_;
    # See - https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html
#    return 'https://sso.hivehome.com/auth/login?client=v3-web-prod';    
    return 'https://cognito-idp.'.$self->{region}.'.amazonaws.com/';
}

sub _getHeaders($$) {
    my ($self, $text) = @_;
    my $header = [  'X-Amz-Target' => 'AWSCognitoIdentityProviderService.'.$text
                ,   'Content-Type' => 'application/x-amz-json-1.1'];
    return $header;
}

sub _log($$$)
{
    my ( $self, $loglevel, $text ) = @_;

    my $xline = (caller(0))[2];
    my $xsubroutine = (caller(1))[3];
    my $sub = (split( ':', $xsubroutine ))[2];

    main::Log3("AWSCognitoIdp", $loglevel, "$sub.$xline ".$text);
}

sub hash_sha256($$) {
    my ($self, $data) = @_;
    my $temp = sha256_hex($data);
    my $hash = sprintf('%-*s', 64, $temp);
    return $hash;
}

sub bigIntHash($$) {
    my ($self, $value) = @_;
    return $self->hexHash($value->to_hex());
}

sub hexHash($$) {
    my ($self, $valueHex) = @_;
    # Convert the value to binary.
    my $bytes = pack("H*", $valueHex);
    return $self->hash_sha256($bytes);
}

sub padHex($$) {
    my ($self, $hexValue) = @_;
    if (length($hexValue) % 2 == 1) {
        $hexValue = '0'.$hexValue;
    } elsif (index('89ABCDEFabcdef', substr($hexValue, 0, 1)) != -1) {
        $hexValue = '00'.$hexValue;
    }
    return $hexValue;
}

sub generateRandom($$) {
    my ($self, $sizeBytes) = @_;
    my @set = ('0' ..'9', 'A' .. 'F');
    my $str = join '' => map $set[rand @set], 1 .. $sizeBytes*2;
    return Math::BigInt->from_hex($str);
}

sub generateSmallA($) {
    my ($self) = @_;
    my $rnd = $self->generateRandom(128);
#    $rnd = Math::BigInt->new('114904749852874150273628708634582749044919403962151865244934285010698547700791149832387866823900365467026537191888308048799874366290794003128650060077194494730597227875928924102246052857515030111400777672253681955955944686047144996265348153531089337796426863174151635891118412829059735517767631010442501261030');
    return $rnd->bmod($self->{BIG_N});
}

sub generateLargeA($) {
    my ($self) = @_;
    my $bigA = $self->{G}->copy()->bmodpow($self->{smallA}, $self->{BIG_N});
    if ($bigA->bmod($self->{BIG_N}) == 0) {
        # Error...
        $bigA = undef;
    }
    return $bigA;
}

# See - https://github.com/amazon-archives/amazon-cognito-auth-js/blob/v1.3.2/src/CognitoAuth.js#L759
# Function call getUserContextData (bottom of script)
# Call to AmazonCognitoAdvancedSecurityData
sub generateUserContextData($) {
    my ($self) = @_;

    # TODO: work in progress... It is not a mandatory element.... yet....

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
            ,   username => $self->{userName}
            ,   userPoolId => $self->{region}.'_'.$self->{poolId}
            ,   timestamp => $timestamp
        };

    my $signature = ''; # Base64 encoded signature of the payload object.
    my $version = 'JS20171115';

    my $userContextData = {
            payload => $payload
        ,   signature => $signature
        ,   version => $version
        };

    return $userContextData;
}

sub calculateU($$) {
    #Calculate the client's value U which is the hash of A and B.
    my ($self, $largeA, $serverB) = @_;
    my $uHex = $self->hexHash($self->padHex($largeA->to_hex()).$self->padHex($serverB->to_hex()));
    return Math::BigInt->from_hex($uHex);
}

sub computeHKDF($$) {
    my ($self, $ikmHex, $saltHex) = @_;
    my $pk = hmac_sha256(pack("H*", $ikmHex), pack("H*", $saltHex));
    my $varInfoBits = $INFO_BITS.chr(1);
    my $hmac_hash = hmac_sha256($varInfoBits, $pk);
    return substr($hmac_hash, 0, 16);
}

sub getPasswordAuthenticationKey($$$$) {
    my ($self, $userId, $srpB, $saltHex) = @_;

    my $serverB = Math::BigInt->from_hex($srpB);
    my $uValue = $self->calculateU($self->{largeA}, $serverB);
    # TODO: verify u - must not be 0.

    my $usernamePassword = $self->{poolId}.$userId.':'.$self->{password};
    my $usernamePasswordHash = $self->hash_sha256($usernamePassword);

    my $xValue = Math::BigInt->from_hex($self->hexHash($self->padHex($saltHex).$usernamePasswordHash));

    my $gModPowXN = $self->{G}->copy()->bmodpow($xValue, $self->{BIG_N});
    my $intVal2 = $serverB->bsub($self->{K}->bmul($gModPowXN));
    my $sValue = $intVal2->bmodpow($self->{smallA}->badd($uValue->copy()->bmul($xValue)), $self->{BIG_N});

    return $self->computeHKDF($self->padHex($sValue->to_hex()), $self->padHex($uValue->to_hex()));
}
