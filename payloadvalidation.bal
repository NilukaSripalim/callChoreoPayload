import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/cache;

// Configurations
configurable string asgardeoUrl = ?;
configurable OAuth2App asgardeoAppConfig = ?;
configurable string redisHost = ?;
configurable int retryCount = 3;
configurable int waitTime = 5000; // in milliseconds

// Type definitions
type OAuth2App record {|
    string clientId;
    string clientSecret;
    string tokenEndpoint;
|};

type AsgardeoUser record {|
    string userName;
    Name name;
    string password;
    Email email;
|};

type Name record {|
    string givenName;
    string familyName;
|};

type Email record {|
    string value;
    boolean primary;
|};

type AsgardeoGetUserResponse record {|
    string id;
    string userName;
    string urn:scim:wso2:schema.is_migrated;
|};

// HTTP Client for Asgardeo
final http:Client asgardeoClient = check new (asgardeoUrl, {
    auth: {
        clientId: asgardeoAppConfig.clientId,
        clientSecret: asgardeoAppConfig.clientSecret,
        tokenEndpoint: asgardeoAppConfig.tokenEndpoint,
        scopes: "internal_user_mgt_create"
    }
});

// Redis connection configuration
cache:Client conn = check new(redisHost);

isolated function createUserInAsgardeo(json jsonObj, string correlationID) returns json|error? {
    final string userName = check jsonObj.userName;
    final json & readonly userobj = <readonly>jsonObj;

    // Check cache
    int|error existResult = conn->exists(["au_".concat(userName)]);
    if (existResult is error) {
        log:printError("Error while checking the Redis cache: " + existResult.toString(), correlationID);
        return error("Cache check failed.");
    } else if (existResult == 1) {
        string|error? userIDResponse = conn->get("au_".concat(userName));
        if (userIDResponse is error) {
            log:printError("Error while getting cache entry from Redis: " + userIDResponse.toString(), correlationID);
            return error("Cache retrieval failed.");
        }
        log:printInfo("User found in cache: " + <string>userIDResponse, correlationID);
        return (<string>userIDResponse).fromJsonString();
    } else {
        log:printInfo("User not found in cache: " + userName, correlationID);
    }

    worker w1 returns json|error? {
        log:printInfo("Starting user creation process in Asgardeo", correlationID);
        boolean retryFlow = true;
        int currentRetryCount = 0;

        while (retryFlow && currentRetryCount < retryCount) {
            http:ClientConfiguration httpClientConfig = {
                httpVersion: "1.1",
                timeout: 20000
            };

            log:printInfo("Creating Asgardeo client", correlationID);
            http:Client httpClient = new (asgardeoUrl, httpClientConfig);
            
            // Check if the user already exists
            http:Response|http:ClientError getResponse = httpClient->get("/scim2/Users?filter=userName+eq+" + userName + "&attributes=id", {"Authorization": "Bearer " + asgardeoAppConfig.clientId});
            if (getResponse is error) {
                log:printError("Error while getting the user information from Asgardeo: " + getResponse.toString(), correlationID);
            } else {
                json|error getRespPayload = getResponse.getJsonPayload();
                if (getRespPayload is error) {
                    log:printError("Error while extracting the JSON response: " + getRespPayload.toString(), correlationID);
                } else {
                    int totalResults = check getRespPayload.totalResults;
                    log:printInfo("Total user results: " + totalResults.toString(), correlationID);

                    if (totalResults == 1) {
                        json[] resources = check getRespPayload.Resources.ensureType();
                        json userIdJson = resources[0];
                        
                        // Cache the user information
                        string|error setCacheResponse = conn->pSetEx("au_".concat(userName), userIdJson.toJsonString(), 86400000);
                        if (setCacheResponse is error) {
                            log:printError("Error while inserting the entry to Redis cache: " + setCacheResponse.toString(), correlationID);
                        } else {
                            retryFlow = false;
                            log:printInfo("User added to cache successfully.", correlationID);
                        }
                    } else {
                        // Create user if not found
                        log:printInfo("User not found in Asgardeo, creating new user", correlationID);
                        time:Utc beforeInvoke = time:utcNow();
                        
                        http:Response postResponse = check httpClient->post("/scim2/Users", userobj, {"Authorization": "Bearer " + asgardeoAppConfig.clientId});
                        json respPayload = check postResponse.getJsonPayload();
                        log:printInfo("Asgardeo user creation response: " + respPayload.toJsonString(), correlationID);
                        
                        time:Utc afterInvoke = time:utcNow();
                        time:Seconds respondTime = time:utcDiffSeconds(beforeInvoke, afterInvoke);
                        log:printInfo("Asgardeo User Creation latency: " + respondTime.toString(), correlationID);
                        
                        // Cache the newly created user
                        string|error setCacheResponse = conn->pSetEx("au_".concat(userName), respPayload.toJsonString(), 86400000);
                        if (setCacheResponse is error) {
                            log:printError("Error while inserting the entry to Redis cache: " + setCacheResponse.toString(), correlationID);
                        } else {
                            retryFlow = false;
                            log:printInfo("User added to cache successfully after creation.", correlationID);
                        }
                    }
                }
            }
            runtime:sleep(waitTime);
            currentRetryCount += 1;
        }
    }
    
    log:printInfo("Response for createUserInAsgardeo endpoint: Accepted. Asgardeo user being created", correlationID);
    return {"status": "Accepted. Asgardeo user being created"};
}
