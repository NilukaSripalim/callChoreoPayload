import ballerina/http;
import ballerina/log;

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
       json jsonObj = check value:fromJsonString(jsonString);

       // Log the received JSON payload (optional for debugging purposes)
       log:printInfo("Received JSON Payload: " + jsonString);

       json|error jsonObj = value:fromJsonString(jsonString);
       if (jsonObj is error) {
        log:printError("Error occurred while parsing the JSON payload: " + jsonObj.message());
       return;
    }
   }
}
