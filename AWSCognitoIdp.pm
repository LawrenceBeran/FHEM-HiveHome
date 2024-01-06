package AWSCognitoIdp;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use REST::Client;
use JSON;
use Data::Dumper;
use POSIX qw(strftime);
use MIME::Base64;
use Digest::SHA qw(sha256_hex hmac_sha256_hex hmac_sha256);
use Math::BigInt lib => 'GMP';
use Carp qw(croak);
use Encode qw(decode encode);


my $PASSWORD_VERIFIER_CHALLENGE = "PASSWORD_VERIFIER";
my $DEVICE_VERIFIER_CHALLENGE   = "DEVICE_SRP_AUTH";

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

    croak "Illegal parameter list has incorrect number of values" if @_ % 2;

    my %params = @_;

    my $self = {};              # the internal structure we'll use to represent
                                # the data in our class is a hash reference
    bless( $self, $class );     # make $self an object of class $class

    # This could be abstracted out into a method call if you 
    # expect to need to override this check.
    for my $required (qw{ userName password }) {
        croak "Required parameter '$required' not passed to '$class' constructor"
            unless exists $params{$required};  
    }

    # initialise class members, these can be overriden by class initialiser.
    $self->{userName}   = undef;
    $self->{password}   = undef;

    $self->{deviceGroupKey} = undef;
    $self->{deviceKey}      = undef;
    $self->{devicePassword} = undef;

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
    $self->{userID} = "user_id";

    $self->{ua} = LWP::UserAgent->new;

    $self->{region}     = undef;
    $self->{poolId}     = undef;
    $self->{clientId}   = undef;
    $self->{clientSecret} = undef;

    $self->{BIG_N}  = undef;
    $self->{G}      = undef;
    $self->{K}      = undef;
    $self->{smallA} = undef;
    $self->{largeA} = undef;

    $self->_getLoginInfo();

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
sub deviceGroupKey($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{deviceGroupKey} = $value;
    }
    return $self->{deviceGroupKey};
}
# Attribute accessor method.
sub deviceKey($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{deviceKey} = $value;
    }
    return $self->{deviceKey};
}
# Attribute accessor method.
sub devicePassword($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{devicePassword} = $value;
    }
    return $self->{devicePassword};
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

sub confirmDevice($$) {
    my ($self, $respChallengeResponse) = @_;

    if ($respChallengeResponse->{NewDeviceMetadata}->{DeviceKey}) {

        # See - https://aws.amazon.com/premiumsupport/knowledge-center/cognito-user-pool-remembered-devices/
        #       https://stackoverflow.com/questions/52499526/device-password-verifier-challenge-response-in-amazon-cognito-using-boto3-and-wa
        # For details on how to make this call.

        my $devicePassword = decode('UTF-8', encode_base64($self->generateRandom(40), ''));

        my $metaData = $respChallengeResponse->{NewDeviceMetadata};
        my $combinedString = $metaData->{DeviceGroupKey}.$metaData->{DeviceKey}.':'.$devicePassword;
        my $combinedStringHash = $self->hash_sha256(encode('UTF-8', $combinedString));
        my $salt = $self->padHex($self->generateRandom(16)->to_hex());
        my $x_value = Math::BigInt->from_hex($self->hexHash($salt.$combinedStringHash));
        my $paswordVerifier = $self->toBytearrayFromHex($self->padHex($self->{G}->copy()->bmodpow($x_value, $self->{BIG_N})->to_hex()));

        my $dataConfirmDevice = {
                AccessToken => $respChallengeResponse->{AccessToken}
            ,   DeviceKey => $metaData->{DeviceKey}
            ,   DeviceName => 'UserAgent'
            ,   DeviceSecretVerifierConfig => { 
                    PasswordVerifier => decode('UTF-8', encode_base64($paswordVerifier, ''))
                ,   Salt => decode('UTF-8', encode_base64($self->toBytearrayFromHex($salt), ''))
               }
            } ;

        my $respConfirmDeviceResponse = $self->_postData($dataConfirmDevice, $self->_getHeaders('ConfirmDevice'));

        # TODO: Not sure if this response means I need to do anything else, but I can now
        #       refresh the clients tokens so probs nothing more is required.
        if ($respConfirmDeviceResponse->{UserConfirmationNecessary}) {

            # Need to provide response!
            my $val = '';
        }

        $self->{devicePassword} = $devicePassword;

        my $updateDeviceStatus = {
                AccessToken => $respChallengeResponse->{AccessToken}
            ,   DeviceKey => $metaData->{DeviceKey}
            ,   DeviceRememberedStatus => 'remembered'
            };

        my $respUpdateDeviceStatus = $self->_postData($updateDeviceStatus, $self->_getHeaders('UpdateDeviceStatus'));        

    }
}

sub getDeviceData($) {
    my ($self) = @_;

    return ($self->{deviceGroupKey}, $self->{deviceKey}, $self->{devicePassword});
}

sub loginSMS2FA($$$) {
    my ($self, $code, $session) = @_;

    my $dataChallengeResponse = {
            ClientId => $self->{clientId}
        ,   ChallengeName => 'SMS_MFA'
        ,   Session => $session
        ,   ChallengeResponses => {
                SMS_MFA_CODE => $code
            ,   USERNAME => $self->{userID}
        }
    };

    $dataChallengeResponse = $self->_addUserContextData($dataChallengeResponse);
    my $dataChallengeResponseResponse = $self->_postData($dataChallengeResponse, $self->_getHeaders('RespondToAuthChallenge'));

    if (defined($dataChallengeResponseResponse) && defined($dataChallengeResponseResponse->{AuthenticationResult}) && defined($dataChallengeResponseResponse->{AuthenticationResult}->{NewDeviceMetadata})) {
        $self->{deviceGroupKey} = $dataChallengeResponseResponse->{AuthenticationResult}->{NewDeviceMetadata}->{DeviceGroupKey};
        $self->{deviceKey}      = $dataChallengeResponseResponse->{AuthenticationResult}->{NewDeviceMetadata}->{DeviceKey};
    }

    return $dataChallengeResponseResponse;
}

sub loginDevice($) {
    my ($self) = @_;

    # 'Device group key', 'device key name' and 'device password' must be provided to login using this method.
    
    my $loginResult = $self->loginSRP();
    if ($loginResult->{ChallengeName} ne $DEVICE_VERIFIER_CHALLENGE) {
        $self->_log(1, 'The '.$loginResult->{ChallengeName}.' challenge is not supported!');
        return undef;
    }

    my $dataAuth = $self->_getAuthParams();
    my $authChallengeResponse = {
            ClientId => $self->{clientId}
        ,   ChallengeName => $DEVICE_VERIFIER_CHALLENGE
        ,   ChallengeResponses => $dataAuth
        };

    my $respChallengeResponse = $self->_challengeResponse($authChallengeResponse);
    if (!$respChallengeResponse) {
        $self->_log(1, 'Error in call to challengeResponse!');
        return undef;
    }

    # Process device challange...
    my $challangeParameters = $respChallengeResponse->{ChallengeParameters};

    # Generate the response
    my $userName = $challangeParameters->{USERNAME};
    my $saltHex = $challangeParameters->{SALT};
    my $srpBHex = $challangeParameters->{SRP_B};
    my $secretBlockB64 = $respChallengeResponse->{ChallengeParameters}->{SECRET_BLOCK};
    my $timeStamp = strftime("%a %b %d %H:%M:%S UTC %Y", localtime());
    $timeStamp =~ s/ 0(\d) / $1 /ig;

    # my $userName = 'lawrence.beran@gmail.com';
    # my $saltHex = 'e40c8d7cddfbabdfd3e3c58160a49662';
    # my $srpBHex = 'a14818c661d18fb01abac64eeda348536f791427877079231edff4d940b9c8c6d001677de0422c483caab82ce0b957d66b11786bf70730716d1946bdbfce7550383a82077b6aeb01048a198b016b2c70d4dab69c207c2a5a90c865478d2c9077fd8f61e23232ce38967bb8901c1f6260566e8a0baa14800b5adb6f4c53aca14349a43698174c90275e8edbaa64ec3d89707d47c864666277fe16fa9fba67331e472fd746faefc14091780766635f7aa681aa16a4708bc1f04b50324bb76a595ea0d0be277ef7ee1b02ce154ae2f42e0ff3611827a62cb65f516d7d7e87f69d09b3cf154bf07e4437d7289c0615d329ab34eb2ff11b2028724f63f8ab7edc4cbf5dec6538033f74a3a78509a0631f00e12e3992906fdbf79a58894284a562304314e1238b7020eb0d83dac23d2587c3d0e723b76453404a4a45b7868b777c15716d814e3f667b10802e058e3af1c6d550a60ab2300f588966c4c8c2a59fa82aee6c45392740bfdb482bf23c87be1d91be46afe2234aed87426acb4921b334716e';
    # my $secretBlockB64 = 'BzAQ76nTV4O79/wpoXwPQu/u5WvBVh8gCVE5KrmRfTY4NJin2q9kLdmy8iexceu8Ygl1pckPmD4rwS6VnV6s05Zls7eRjaNgQ1L+hxuda1xV5a9a9EkSJ6iBmj79LsneW9xVqlROGD+t0zouYhAlh/JnaU9duc6GH90DJSS+l3zEv1UTl/hM7nPtg9QGb97MmYJXWb6L9qWHGoz0pHX7ydkXhLFwtdOhxR6D/rMa46WCuAIiooPnGZIlyswbPtaZKAWZpcyYFgUSWctszfCv/jJeShrnHIufkVI469zjJvlRpXw9ajUKa15oX/ARzf+vFAsRLNOLmayb4zWHE+tuAvgpJQFb2H6AWVckyu8uZqXXxZ1jFZ25W4A5fU5PaoTr8n7RJ0IOTe4DmWhTSMxSINdh7xaUK0Msf/ujr1c8zIuSCEda2WkhbOKt6YqRPSdmppLuwPRAaT+QPuRitYcqXqEuhPrDWCyAVyujBzKUqlsHYZK4FwM2qmpgn4FJpztSoeL67MJRuS16gQAiox8SpjlsxO384dhLVtjhe/NDoPa2pOsB66MNORWjs1AK6MLfhNeN3R21Bbe7IBWzbfAqW5LCR0xjKXk3551Xm3vQYABPS9rhfi2ItQi1s+T3Kyej+CIyNa8rgOd0ZAgQXYFKy1i3DTaP4s5KDm3TgQv2/gFL4uDRGmZajvX5Qq5kEXCKDMfz5UidnJWURT+FKVjJ4JQW2DSDKeiFtdopl/wewxpe1YvkI+PM7qdE5WliPfQKF6Kr9Y1cPe7UIZ4UiK+5behrneNiffxRwcM6RImMnHO1McAGQiuREYbSF/6B36eKbrL36WoyDV+3WzUz5W1SVIGUz3i93ewhNwx9BQ5kyckIiLo5xNmiN0ckowOatkWYslI3z74l/6a3b6d6V1bSta1+EKVjhUDIk8zpxqXGNeGyuJBww8uornJBHDugBOhfYSIA1lPzLpeP13SDW68PBZDuGxcx8FyxA6J1IHcSR81960n6KJkhcVYVNjCoZPmPITE9WmCCAy3GVz2E7HhGAy2RbC0dLIlcyX3q/OZIE5LvYRu6lHrheisfhjPZXJMd7hAU7n+ywHu5eYP0cfIjDPv8o5dC1rOYNIFTHZf7eOHFgzKvwy2EpIbFaXXzaHRzwyBeZ5iUarK09AucqkqzharvlQFS4HJYoE7nz/Uzy/cyNJm3bg+Dr9jlWclGDTasywdMGmyxEOj1dqW5OXruDRreov8t1KS5E/d5UJfqIPH98dOP9pO4URMGQGtKyLPqMRbgKeALe2e2rW67eZP+x8Y26q03c7u7mlJidEyDLcM68ZHOwSRiJ70vLXLs54hlYP9v94JNkjIpmEbygES3L2JexAcn1DqSQi9ObK8IBssgMmt2tlExETmRc/Y2KiBUh2EaTY+tbn2mTKphy7W/AIJ6qFhmwg+gYJLyb4jn1e0wsVw6WnadWO16jU3SOKfGgXQPD/XxDFZW1doFWspDOkUlL2jU5/uSuI+9dJlXBOH65W9RNgJDnKjwEibG/j31EsgHaSWBPwVgaKh5clw8Lqd+CfY1XWQGyS9PDOlRrgk4fy+e93V1J/Z4WUQ+iunhHbDQQt/PPbDEXGjVRhgRf8bW19dRSzLtTAu/Ebb1UZUYS9q2zyt7LEK5/UTAdKE/lwQsNsGecVHsnCT/YdfSvZBzEdoHPYMY1NsYXsa/n83ZW1gSsIRZQKrIkw==';
    # my $timeStamp = 'Mon Jun 12 22:27:43 UTC 2023';

    my $hkdf = $self->getDeviceAuthenticationKey($self->{deviceGroupKey}, $self->{deviceKey}, $self->{devicePassword}, $srpBHex, $saltHex);
    my $secretBlock = decode_base64($secretBlockB64);
    my $msg = $self->{deviceGroupKey}.$self->{deviceKey}.$secretBlock.$timeStamp;

    my $signature = encode_base64(hmac_sha256($msg, $hkdf), '');

    my $deviceChallangeResponse = {
            ClientId => $self->{clientId}
        ,   ChallengeName => 'DEVICE_PASSWORD_VERIFIER'
        ,   ChallengeResponses => {
                TIMESTAMP => $timeStamp
            ,   USERNAME => $userName
            ,   PASSWORD_CLAIM_SECRET_BLOCK => $secretBlockB64
            ,   PASSWORD_CLAIM_SIGNATURE => decode('UTF-8', $signature)
            ,   DEVICE_KEY => $self->{deviceKey}
            }
        };

    my $respDeviceChallengeResponse = $self->_challengeResponse($deviceChallangeResponse);
    if (!$respDeviceChallengeResponse) {
        $self->_log(1, 'Error in call to challengeResponse!');
        return undef;
    }

    return $respDeviceChallengeResponse;
}

sub loginSRP($) {
    my ($self) = @_;

    # See for the call order if devices are required to be used for refresh tokens.
    # https://aws.amazon.com/premiumsupport/knowledge-center/cognito-user-pool-remembered-devices/

    
    my $dataAuth = {
            AuthFlow => 'USER_SRP_AUTH'
        ,   ClientId => $self->{clientId}
        ,   AuthParameters => $self->_getAuthParams()
        };

    my $dataInitAuth = $self->_initAuthentication($dataAuth);

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

    $self->{userID} = $challangeParameters->{USER_ID_FOR_SRP};
    my $saltHex = $challangeParameters->{SALT};
    my $srpBHex = $challangeParameters->{SRP_B};
    my $secretBlockB64 = $challangeParameters->{SECRET_BLOCK};
    my $secretBlock = decode_base64($secretBlockB64);

    my $timeStamp = strftime("%a %b %d %H:%M:%S UTC %Y", localtime());
    $timeStamp =~ s/ 0(\d) / $1 /ig;

    my $hkdf = $self->getPasswordAuthenticationKey($self->{userID}, $srpBHex, $saltHex);
    my $msg = $self->{poolId}.$self->{userID}.$secretBlock.$timeStamp;
    my $signature = encode_base64(hmac_sha256($msg, $hkdf), '');

    my $dataChallengeResponse = {
            ChallengeResponses => {
                USERNAME => $self->{userID}
            ,   PASSWORD_CLAIM_SECRET_BLOCK => $secretBlockB64
            ,   TIMESTAMP => $timeStamp
            ,   PASSWORD_CLAIM_SIGNATURE => $signature
            }
        ,   ChallengeName => $PASSWORD_VERIFIER_CHALLENGE
        ,   ClientId => $self->{clientId}
        };

    if (defined($self->{deviceKey})) {
        $dataChallengeResponse->{ChallengeResponses}->{DEVICE_KEY} = $self->{deviceKey};
    }

    my $respChallengeResponse = $self->_challengeResponse($dataChallengeResponse);
    if (!$respChallengeResponse) {
        $self->_log(1, 'Error in call to challengeResponse!');
        return undef;
    }

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

    my $refreshTokenAuthResp = $self->_initAuthentication($refreshTokenAuth);

    if (!$refreshTokenAuthResp) {
        return undef;
    }

    return $refreshTokenAuthResp->{AuthenticationResult};
}


#############################
#   Internal helper methods
#############################

sub _initAuthentication($$) {
    my ($self, $dataAuth) = @_;

    #
    # Initiate authentication...
    #   - https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html
    #

    $dataAuth = $self->_addUserContextData($dataAuth);
    my $dataAuthResponse = $self->_postData($dataAuth, $self->_getHeaders('InitiateAuth'));
    return $dataAuthResponse;
}

sub _challengeResponse($$) {
    my ($self, $dataChallengeResponse) = @_;

    $dataChallengeResponse = $self->_addUserContextData($dataChallengeResponse);
    my $dataChallengeResponseResponse = $self->_postData($dataChallengeResponse, $self->_getHeaders('RespondToAuthChallenge'));
    return $dataChallengeResponseResponse;
}

sub _getAuthParams($) {
    my ($self) = @_;

    # Prepare SRP details for authentication.
    if (!defined($self->{largeA})) {

        $self->{BIG_N}  = Math::BigInt->from_hex($N_HEX);
        $self->{G}      = Math::BigInt->from_hex($G_HEX);
        $self->{K}      = Math::BigInt->from_hex($self->hexHash('00'.$N_HEX.'0'.$G_HEX));

        $self->{smallA} = $self->generateSmallA();
        $self->{largeA} = $self->generateLargeA();
    }

    my $dataAuth = {
            SRP_A => $self->{largeA}->to_hex()
        ,   USERNAME => $self->{userName}
        };

    if (defined($self->{deviceKey})) {
        $dataAuth->{DEVICE_KEY} = $self->{deviceKey};
    }

    return $dataAuth;
}

sub _getLoginInfo($) {
    my ($self) = @_;

    my $loginClient = REST::Client->new();
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

    ($self->{region}, $self->{poolId}) = (split('_', $data->{HiveSSOPoolId}))[0,1];
    $self->{clientId} = $data->{HiveSSOPublicCognitoClientId};    
}

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

sub toBytearrayFromHex($$) {
    my ($self, $valueHex) = @_;
    # Convert the value to binary.
    return pack("H*", $valueHex);
}

sub hexHash($$) {
    my ($self, $valueHex) = @_;
    # Convert the value to binary.
    return $self->hash_sha256($self->toBytearrayFromHex($valueHex));
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
#    $rnd = Math::BigInt->new('39148421268336541158259990642813454561836501360707832680114038241931293644645766112174300479390491376262488826735239943774587068673406883674275592235070513278839823949338880243352980930276649694788047372741129037402486966288621369429732317989456974230705067882321056819817057381981655308968092729793171466256');
    return $rnd->bmod($self->{BIG_N});
}

sub generateLargeA($) {
    my ($self) = @_;
    my $bigA = $self->{G}->copy()->bmodpow($self->{smallA}->copy(), $self->{BIG_N});
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

sub calculateU($$$) {
    #Calculate the client's value U which is the hash of A and B.
    my ($self, $largeA, $serverB) = @_;
    my $uHex = $self->hexHash($self->padHex($largeA->to_hex()).$self->padHex($serverB->to_hex()));
    return Math::BigInt->from_hex($uHex);
}

sub computeHKDF($$$) {
    my ($self, $ikmHex, $saltHex) = @_;
    my $pk = hmac_sha256($self->toBytearrayFromHex($ikmHex), $self->toBytearrayFromHex($saltHex));
    my $varInfoBits = $INFO_BITS.chr(1);
    my $hmac_hash = hmac_sha256($varInfoBits, $pk);
    return substr($hmac_hash, 0, 16);
}

sub getDeviceAuthenticationKey($$$$$$) {
    my ($self, $deviceGroupKey, $deviceKey, $devicePassword, $srpB, $saltHex) = @_;

    my $usernamePassword = $deviceGroupKey.$deviceKey.':'.$devicePassword;
    return $self->getUsernamePasswordAuthenticationKey($usernamePassword, $srpB, $saltHex);
}

sub getPasswordAuthenticationKey($$$$) {
    my ($self, $userId, $srpB, $saltHex) = @_;

    my $usernamePassword = $self->{poolId}.$userId.':'.$self->{password};
    return $self->getUsernamePasswordAuthenticationKey($usernamePassword, $srpB, $saltHex);
}

sub getUsernamePasswordAuthenticationKey($$$$) {
    my ($self, $usernamePassword, $srpB, $saltHex) = @_;

    my $serverB = Math::BigInt->from_hex($srpB);
    my $uValue = $self->calculateU($self->{largeA}, $serverB);
    # TODO: verify u - must not be 0.

    my $usernamePasswordHash = $self->hash_sha256(encode('UTF-8', $usernamePassword));

    my $xValue = Math::BigInt->from_hex($self->hexHash($self->padHex($saltHex).$usernamePasswordHash));
    my $gModPowXN = $self->{G}->copy()->bmodpow($xValue, $self->{BIG_N});
    my $intVal2 = $serverB->bsub($self->{K}->copy()->bmul($gModPowXN));
    my $sValue = $intVal2->copy()->bmodpow($self->{smallA}->copy() + $uValue * $xValue, $self->{BIG_N});

    return $self->computeHKDF($self->padHex($sValue->to_hex()), $self->padHex($uValue->to_hex()));
}