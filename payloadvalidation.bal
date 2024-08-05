import ballerina/http;
import ballerina/log;

configurable string asgardeoUrl = ?;
configurable OAuth2App asgardeoAppConfig = ?;
final string asgardeoScopesString = string:'join(" ", ASGARDEO_USER_VIEW_SCOPE);

type OAuth2App record {|
    string clientId;
    string clientSecret;
    string tokenEndpoint;
|};

type UserName record {|
    string givenName;
    string familyName;
|};

type Email record {|
    string value;
    boolean primary;
|};

type AsgardeoUser record {|
    string userName;
    UserName name;
    string password;
    Email email;
|};

final http:Client asgardeoClient = check new (asgardeoUrl, {
    auth: {
        scheme: http:OAUTH2,
        config: asgardeoAppConfig,
        scopes: string:split(asgardeoScopesString, " ")
    }
});

# Creates a new user in the Asgardeo user store. Uses Asgardeo SCIM 2.0 API.
# 
# + user - Asgardeo User data
# + return - Created Asgardeo user data if successful, else an `error`
isolated function createAsgardeoUser(AsgardeoUser user) returns AsgardeoUser|error {
    // Define the payload for creating a new user
    json payload = {
        "schemas": [],
        "userName": user.userName,
        "name": {
            "givenName": user.name.givenName,
            "familyName": user.name.familyName
        },
        "password": user.password,
        "emails": [
            {
                "value": user.email.value,
                "primary": user.email.primary
            }
        ]
    };

    // Send POST request to create the user
    http:Response response = check asgardeoClient->/scim2/Users.post(payload);

    if response.statusCode != http:STATUS_CREATED {
        json|error jsonPayload = response.getJsonPayload();
        log:printError(string `Error while creating user. ${jsonPayload is json ? jsonPayload.toString() : response.statusCode}`);
        return error("Error while creating user.");
    }

    // Return the created user data
    json createdUserPayload = check response.getJsonPayload();
    return {
        userName: createdUserPayload.userName.toString(),
        name: {
            givenName: createdUserPayload.name.givenName.toString(),
            familyName: createdUserPayload.name.familyName.toString()
        },
        password: user.password, // Password is usually not returned in the response
        email: {
            value: createdUserPayload.emails[0].value.toString(),
            primary: createdUserPayload.emails[0].primary
        }
    };
}
