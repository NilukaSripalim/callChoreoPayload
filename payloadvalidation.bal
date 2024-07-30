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

       // Prepare the response with the same JSON payload
       http:Response response = new;
       response.statusCode = http:STATUS_CREATED; // Set status code to 201 Created
       response.setJsonPayload(jsonObj);
       
       // Send the response back to the client
       check caller->respond(response);
   }
}
