import ballerina/http;
import ballerina/lang.regexp;
import ballerina/log;

configurable string asgardeoUrl = ?;
configurable OAuth2App asgardeoAppConfig = ?;
final string asgardeoScopesString = "internal_user_mgt_create";

type OAuth2App record {|
    string clientId;
    string clientSecret;
    string tokenEndpoint;
|};

@display {
    label: "Asgardeo Client",
    id: "asgardeo/client"
}
final http:Client asgardeoClient = check new (asgardeoUrl, {
    auth: {
        clientId: asgardeoAppConfig.clientId,
        clientSecret: asgardeoAppConfig.clientSecret,
        tokenEndpoint: asgardeoAppConfig.tokenEndpoint,
        scopes: asgardeoScopesString
    }
});

# Checks the health of the Asgardeo server. Uses Asgardeo SCIM 2.0 API.
# 
# + return - `()` if the server is reachable, else an `error`
isolated function checkAsgardeoHealth() returns error? {
    http:Response response = check asgardeoClient->/scim2/ServiceProviderConfig.get();
    if response.statusCode != http:STATUS_OK {
        return error("Asgardeo server is not reachable.");
    }
}

# Fetches the user using ID from the Asgardeo user store. Uses Asgardeo SCIM 2.0 API.  
# Get User by ID - https://wso2.com/asgardeo/docs/apis/scim2/#/operations/getUser%20by%20id
#
# + id - User ID
# + return - Asgardeo user data if the user is found, else an `error`
isolated function getAsgardeoUser(string id) returns AsgardeoUser|error {
    AsgardeoGetUserResponse|http:ClientError response = asgardeoClient->/scim2/Users/[id].get();
    if response is http:ClientError {
        log:printError(string `Error while fetching user.`, response);
        return error("Error while fetching user.");
    }

    regexp:Span? findUserName = REGEX_EXTRACT_EMAIL_FROM_USERNAME.find(response.userName);
    if findUserName is () {
        return error("User not found");
    }

    return {
        id: response.id,
        username: findUserName.substring(),
        isMigrated: response.urn\:scim\:wso2\:schema.is_migrated.toLowerAscii() == "true"
    };
}

# Creates a new user in the Asgardeo user store. Uses Asgardeo SCIM 2.0 API.  
# Create User POST Endpoint - https://wso2.com/asgardeo/docs/apis/scim2/#/operations/createUser
#
# + user - Asgardeo User data
# + return - `()` if the user was created successfully, else an `error`
isolated function createUser(AsgardeoUser user) returns error? {
    json userPayload = {
        "schemas": [
            "urn:ietf:params:scim:api:messages:2.0:User"
        ],
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

    http:Response response = check asgardeoClient->/scim2/Users.post(userPayload);

    if response.statusCode != http:STATUS_CREATED {
        json|error jsonPayload = response.getJsonPayload();
        log:printError(string `Error while creating user. ${jsonPayload is json ?
            jsonPayload.toString() : response.statusCode}`);
        return error("Error while creating user.");
    }
}
