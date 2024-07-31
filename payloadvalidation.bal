import ballerina/http;
import ballerina/log;
import ballerina/jsonutils;

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
    string correlationID;
};

service / on new http:Listener(8090) {
    resource function post echoUserPayload(http:Caller caller, http:Request request) returns error? {
        // Get the JSON payload from the request
        string jsonString = check request.getTextPayload();

        // Log the received JSON payload (optional for debugging purposes)
        log:printInfo("Received JSON Payload: " + jsonString);

        // Parse the JSON string to a JSON object
        json jsonObj = check jsonutils:fromString(jsonString);
        if (jsonObj is json) {
            log:printInfo("Successfully parsed JSON payload");
            
            // Send the parsed JSON object back as the response
            check caller->respond(jsonObj);
        } else {
            log:printError("Error occurred while parsing the JSON payload: " + jsonObj.message());
            check caller->respond(http:STATUS_BAD_REQUEST, { message: "Invalid JSON payload" });
        }
    }
}

