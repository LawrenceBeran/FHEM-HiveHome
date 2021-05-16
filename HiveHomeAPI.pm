package HiveHomeAPI;
use strict;
use warnings;

use REST::Client;
use JSON;
use Data::Dumper;
use MIME::Base64;
use Carp qw(croak);

# Note: The API does not currently care whether the 'heating' or 'hotwater' path is specified as part
# of the /nodes/<heating or hotwater>/<id> endpoint for either heating or hotwater products.
#   A hotwater product id can be specified as part of the heating path and vis-versa.
#
# The API also doesnt respond in failure if invalid parameters are provided to it.
# Most values are tested for validity in this API to rule out errors of that kind.
#

## What is the homeId value... Does that come from the login... Or could a user have multiple homes?
## https://beekeeper-uk.hivehome.com/1.0/nodes/all?products=true&devices=true&actions=true&user=true&homes=true&homeId=<homeId>

## Thermostat - Heat on demand
## https://beekeeper-uk.hivehome.com/1.0/nodes/heating/<id>?homeId=<homeid>
## body (enable):
##  {
##      "autoBoost": "ENABLED"
##  }
## body (disable):
##  {
##      "autoBoost": "DISABLED"
##  }
## body (set auto boost target temperature):
##  {
##      "autoBoostTarget": 21.5
##  }

## TRV - Heat on demand (the thermostate must have heat on demand enabled first)
## https://beekeeper-uk.hivehome.com/1.0/nodes/trvcontrol/<id>?homeId=<homeid>
## Body (disable):
## {
##      "zone": ""
## }
## Body (enable): -- This is the boilermodule id.
## {
##      "zone": "9c45b124-eedf-4310-bb66-d367e929d8d3"
## }

## Heating - Ready by
## https://beekeeper-uk.hivehome.com/1.0/nodes/heating/<id>?homeId=<homeid>
## Body (enable):
## {
##      "optimumStart": true
## }
## Body (disable):
## {
##      "optimumStart": false
## }


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

    $self->{apiVersion} = '1.0';
    $self->{client} = REST::Client->new();
    $self->{client}->setHost('https://beekeeper-uk.hivehome.com:443/1.0/');

    return $self;        # a constructor always returns an blessed() object
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

sub token($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{token} = $value;
    }
    return $self->{token};
}

sub refreshToken($$)
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{refreshToken} = $value;
    }
    return $self->{refreshToken};
}

sub accessToken($$) 
{
    my ($self, $value) = @_;
    if (@_ == 2) 
    {
        $self->{accessToken} = $value;
    }
    return $self->{accessToken};
}

sub getToken($) 
{
    my $self = shift;

    my $token = undef;

    # Ensure we have a valid token.
    $self->_getValidToken();
    if (defined($self->{token}))
    {
        $token = {
                token => $self->{token}
            ,   refreshToken => $self->{refreshToken}
            ,   accessToken => $self->{accessToken}
        };
    }
    return $token;
}

sub apiGET($$) 
{
    my $self = shift;
    my $path = shift;

    my $response = undef;

    $self->_getValidToken();

    if (defined($self->{token}))
    {
        $self->{client}->GET($path, $self->_getHeaders());
        if (200 != $self->{client}->responseCode()) 
        {
            $self->_log(1, "apiGET(path): ${path}");
            $self->_log(1, "apiGET: ".$self->{client}->responseContent());

            # Failed, check the response code to see if the token has expired!
            # Login and try again...
        } 
        else 
        {
            $response = from_json($self->{client}->responseContent());
            $self->_log($self->{logAPIResponsesLevel}, "apiGET(path): ${path}");
            $self->_log($self->{logAPIResponsesLevel}, "apiGET: ".Dumper($response));
        }
    }
    else
    {
        $self->_log(3, "apiGET: No session token");
    }
    return $response;
}

sub apiPOST($$$)
{
    my $self = shift;
    my $path = shift;
    my $data = shift;

    my $response = undef;

    $self->_getValidToken();

    if (defined($self->{token}))
    {
        $self->{client}->POST($path, encode_json($data), $self->_getHeaders());
        if (200 != $self->{client}->responseCode()) 
        {
            $self->_log(1, "apiPOST(path): ${path}");
            $self->_log(1, "apiPOST: ".$self->{client}->responseContent());
            $self->_log(1, "apiPOST(sent): ".Dumper($data));
            $response = from_json($self->{client}->responseContent());

            # Failed, check the response code to see if the token has expired!
            # Login and try again...
        } 
        else 
        {
            $self->_log($self->{logAPIResponsesLevel}, "apiPOST(path): ${path}");
            $self->_log($self->{logAPIResponsesLevel}, "apiPOST(sent): ".Dumper($data));
            $self->_log($self->{logAPIResponsesLevel}, "apiPOST(resp): ".Dumper(from_json($self->{client}->responseContent())));
        }
    }
    else
    {
        $response = "No HiveHome session token!";
    }    
    return $response;
}

sub apiDELETE($$) 
{
    my $self = shift;
    my $path = shift;

    my $response = undef;

    $self->_getValidToken();

    if (defined($self->{token}))
    {
        $self->{client}->DELETE($path, $self->_getHeaders());
        if (200 != $self->{client}->responseCode()) 
        {
            $self->_log(1, "apiDELETE(path): ${path}");
            $self->_log(1, "apiDELETE: ".$self->{client}->responseContent());

            # Failed, check the response code to see if the token has expired!
            # Login and try again...
        } 
        else 
        {
            $response = from_json($self->{client}->responseContent());
            $self->_log($self->{logAPIResponsesLevel}, "apiDELETE(path): ${path}");
            $self->_log($self->{logAPIResponsesLevel}, "apiDELETE(resp): ".Dumper($response));
        }
    }
    else
    {
        $self->log(1, "No HiveHome session token!");
    }
    return $response;
}

######################
# API helper methods

sub _log($$$)
{
    my ( $self, $loglevel, $text ) = @_;

    my $xline = (caller(0))[2];
    my $xsubroutine = (caller(1))[3];
    my $sub = (split( ':', $xsubroutine ))[2];

    main::Log3("Hive", $loglevel, "$sub.$xline " . $text);
}

sub _getHeaders($$) 
{
    my $self = shift;
    my $token = shift;

    my $headers = {
                'Content-Type' => 'application/json'
            ,   'Accept' => 'application/json'
    };

    if (defined($token))
    {
        $headers->{'Authorization'} = $token;
    }
    else 
    {
        if (defined($self->{token})) 
        {
            $headers->{'Authorization'} = $self->{token};
        }
    }

    return $headers;
}

sub _login($) 
{
    my $self = shift;

    $self->{token} = undef;

    my $sessions = {
                username => $self->{userName}
            ,   password => $self->{password}
        };

    my $path = 'cognito/login';
    $self->{client}->POST($path, encode_json($sessions), $self->_getHeaders());
    if (200 != $self->{client}->responseCode()) 
    {
        # Failed to connect to API
        $self->_log(1, "Login: ".$self->{client}->responseContent());
    } 
    else 
    {
        my $response = from_json($self->{client}->responseContent());

        if (defined $response->{user}) 
        {
            $self->{userId}           = $response->{user}{id};
        }
        # Extract the session ID from the response...
        if (defined $response->{token}) 
        {
            $self->{token}          = $response->{token};
            $self->{refreshToken}   = $response->{refreshToken};
            $self->{accessToken}    = $response->{accessToken};
        } 
        else 
        {
            # An error has occured
            $self->_log(1, "Login: ".Dumper(from_json($self->{client}->responseContent())));
            # TODO: break down the error and only report the detail not the JSON
        }

        $self->_log($self->{logAPIResponsesLevel}, "apiPOST(path): ${path}");
        $self->_log($self->{logAPIResponsesLevel}, "apiPOST(sent): ".Dumper($sessions));
        $self->_log($self->{logAPIResponsesLevel}, "apiPOST(resp): ".Dumper(from_json($self->{client}->responseContent())));
    }

    # If undef, then failed to connect!
    return $self->{token};
}

#### 
# Takes a JWT in its basic form as the input parameter, seperates the elements into 
# header, claim and signature parts and then decodes the claim into a JSON object.
# Returns: 
#   undef if the claim cannot be extracted from the token
#   the claim in JSON
sub _getTokenClaim($$)
{
    my $self = shift;
    my $token = shift;

    my $claimJSON = undef;

    if (defined $token)
    {
        my ($headerBase64, $claimBase64, $signatureBase64) = split(/[.]/, $token);

        if (defined $claimBase64)
        {
            my $claimStr = MIME::Base64::decode_base64url($claimBase64);
            $claimJSON = decode_json($claimStr);
        }
    }
    return $claimJSON;
}

#### 
# Takes a JWT as the input parameter, decodes the claim element and checks the 'exp' element
# against the current date/time.
# Returns: 
#   undef if the token is expired or invalid
#   the expiry date/time epoch if the token is valid.
sub _isTokenValid($$) 
{
    my $self = shift;
    my $token = shift;

    my $expired = undef;

    my $tokenClaim = $self->_getTokenClaim($token);
    if (defined $tokenClaim)
    {
        if (defined $tokenClaim->{exp})
        {
            my $currentTime = time;
            if ($tokenClaim->{exp} > $currentTime)
            {
                $expired = $tokenClaim->{exp};
            }
        }
    }

    return $expired;
}

sub _getValidToken($) 
{
    my $self = shift;

    if (defined($self->{token})) 
    {
        # Test the provided session to see if it is valid.
        if (!defined($self->_isTokenValid($self->{token})))
        {
            # Session has expired. Create a new session.
            $self->_log($self->{infoLogLevel}, "connect: Session has expired. requesting new one.");
            $self->{token} = undef;
        }
        else
        {
            $self->_log($self->{infoLogLevel}, "connect: Existing session is valid.");
        }
    }
    else
    {
        # No provided session
        $self->_log($self->{infoLogLevel}, "connect: First time logon (no previous session).");
    }

    if (!defined($self->{token}))
    {
        $self->{token} = $self->_login();
        if (defined($self->{token}))
        {
            $self->_log($self->{infoLogLevel}, "connect: Session created");
        }
        else
        {
            $self->_log(1, "connect: Failed to logon to Hive to create new session.");
        }
    }
    return $self->{token};
}

######################



1;