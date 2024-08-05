import ballerina/http;
import ballerina/log;
import ballerina/lang.string;

configurable string asgardeoUrl = ?;
configurable OAuth2App asgardeoAppConfig = ?;

type OAuth2App record {|
    string clientId;
    string clientSecret;
    string tokenEndpoint;
|};

final string asgardeoScopesString = "internal_user_mgt_create";

@display {
    label: "Asgardeo Client",
    id: "asgardeo/client"
}
final http:Client asgardeoClient = check new (asgardeoUrl, {
    auth: {
        scheme: http:OAUTH2,
        config: {
            tokenUrl: asgardeoAppConfig.tokenEndpoint,
            clientId: asgardeoAppConfig.clientId,
            clientSecret: asgardeoAppConfig.clientSecret,
            scopes: string:split(asgardeoScopesString, " ")
        }
    }
});

type Email record {
    string value;
    boolean primary;
};

type Name record {
    string givenName;
    string familyName;
};

type UserRequest record {
    Email email;
    Name name;
    string userName;
    string password;
};

type AsgardeoUser record {|
    string id;
    string userName;
    boolean isMigrated;
|};

# Creates a user in the Asgardeo user store. Uses Asgardeo SCIM 2.0 API.
# Create User - https://wso2.com/asgardeo/docs/apis/scim2/#/operations/createUser
#
# + user - User data to be created
# + return - Created Asgardeo user data if successful, else an `error`
isolated function createAsgardeoUser(UserRequest user) returns AsgardeoUser|error {
    http:Response response = check asgardeoClient->/scim2/Users.post({
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
    });

    if response.statusCode != http:STATUS_CREATED {
        json|error jsonPayload = response.getJsonPayload();
        log:printError(string `Error while creating user. ${jsonPayload is json ? jsonPayload.toString() : response.statusCode}`);
        return error("Error while creating user.");
    }

    json jsonResponse = check response.getJsonPayload();
    return {
        id: check jsonResponse.id.toString(),
        userName: check jsonResponse.userName.toString(),
        isMigrated: check jsonResponse.urn\:scim\:wso2\:schema.is_migrated.toString().toLowerAscii() == "true"
    };
}

service / on new http:Listener(8090) {
    resource function post create(@http:Payload UserRequest req) returns UserRequest|error? {
        // Log the received request payload for debugging purposes
        log:printInfo("Received payload: " + req.toJsonString());

        // Create a new user in Asgardeo
        var userCreationResult = createAsgardeoUser(req);

        if userCreationResult is AsgardeoUser {
            log:printInfo("User created successfully: " + userCreationResult.toString());
            // Simply return the received request payload as the response
            return req;
        } else {
            log:printError("Failed to create user: ", userCreationResult);
            return userCreationResult;
        }
    }
}
