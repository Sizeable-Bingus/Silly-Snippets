package main

import (
	"encoding/json"
    "encoding/base64"
	"fmt"
)

type httpProfile struct {
    Url     string
    Headers map[string]string
}

func main() {
    profile := httpProfile{
        Url: "http://1.1.1.1",
        Headers: make(map[string]string),
    }
    profile.Headers["header1"] = "value"
    profile.Headers["header2"] = "value2"

    res, err := json.Marshal(profile);
    if (err != nil) {
        return;
    }
    fmt.Println(string(res))

    b64Json := base64.StdEncoding.EncodeToString(res);
    fmt.Println(b64Json);
}
