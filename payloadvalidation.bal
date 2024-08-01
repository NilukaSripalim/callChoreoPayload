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
    resource function post create(@http:Payload UserRequest req) returns UserRequest|error? {
        // Log the received request payload for debugging purposes
        log:printInfo("Received payload: " + req.toJsonString());

        // Simply return the received request payload as the response
        return req;
    }
}
