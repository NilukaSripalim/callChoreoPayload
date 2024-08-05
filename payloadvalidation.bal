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

# Changes the password of the user in the Asgardeo user store. Uses Asgardeo SCIM 2.0 API.  
# Update User PATCH Endpoint - https://wso2.com/asgardeo/docs/apis/scim2/#/operations/patchUser
#
# + user - Asgardeo User data
# + password - New password
# + return - `()` if the password was changed successfully, else an `error`
isolated function changePasswordOfUser(AsgardeoUser user, string password) returns error? {
    http:Response response = check asgardeoClient->/scim2/Users/[user.id].patch({
        "schemas": [
            "urn:ietf:params:scim:api:messages:2.0:PatchOp"
        ],
        "Operations": [
            {
                "op": "replace",
                "value": {
                    "password": password
                }
            },
            {
                "op": "replace",
                "value": {
                    "urn:scim:wso2:schema": {
                        "is_migrated": "true"
                    }
                }
            }
        ]
    });

    if response.statusCode != http:STATUS_OK {
        json|error jsonPayload = response.getJsonPayload();
        log:printError(string `Error while changing password. ${jsonPayload is json ?
            jsonPayload.toString() : response.statusCode}`);
        return error("Error while changing password.");
    }
}
