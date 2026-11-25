package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

func stripVertexIncompatibleFields(body []byte) []byte {
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return body
	}
	contents, ok := payload["contents"].([]any)
	if !ok {
		return body
	}
	modified := false
	for _, c := range contents {
		cm, ok := c.(map[string]any)
		if !ok {
			continue
		}
		parts, ok := cm["parts"].([]any)
		if !ok {
			continue
		}
		for _, p := range parts {
			pm, ok := p.(map[string]any)
			if !ok {
				continue
			}
			if fc, ok := pm["functionCall"].(map[string]any); ok {
				if _, hasID := fc["id"]; hasID {
					delete(fc, "id")
					modified = true
				}
			}
			if fr, ok := pm["functionResponse"].(map[string]any); ok {
				if _, hasID := fr["id"]; hasID {
					delete(fr, "id")
					modified = true
				}
			}
		}
	}
	if !modified {
		return body
	}
	out, err := json.Marshal(payload)
	if err != nil {
		return body
	}
	return out
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func main() {
	listen := flag.String("listen", envOr("VERTEX_LISTEN", "127.0.0.1:8788"), "address to listen on")
	project := flag.String("project", envOr("VERTEX_PROJECT", ""), "GCP project ID or project number (required)")
	location := flag.String("location", envOr("VERTEX_LOCATION", "global"), "Vertex AI / Gemini Platform location")
	flag.Parse()

	if strings.TrimSpace(*project) == "" {
		log.Fatal("missing required GCP project: pass -project <id-or-number> or set VERTEX_PROJECT")
	}

	upstream, err := url.Parse("https://aiplatform.googleapis.com")
	if err != nil {
		log.Fatal(err)
	}

	prefix := "/v1beta1/projects/" + *project + "/locations/" + *location + "/publishers/google/models/"

	proxy := &httputil.ReverseProxy{
		FlushInterval: -1,
		Director: func(req *http.Request) {
			req.URL.Scheme = upstream.Scheme
			req.URL.Host = upstream.Host
			req.Host = upstream.Host

			p := req.URL.Path
			switch {
			case strings.HasPrefix(p, "/v1beta/models/"):
				req.URL.Path = prefix + strings.TrimPrefix(p, "/v1beta/models/")
			case strings.HasPrefix(p, "/v1/models/"):
				req.URL.Path = prefix + strings.TrimPrefix(p, "/v1/models/")
			}
			req.URL.RawPath = ""

			if req.Body != nil && (req.Method == http.MethodPost || req.Method == http.MethodPut) {
				raw, err := io.ReadAll(req.Body)
				_ = req.Body.Close()
				if err == nil && len(raw) > 0 {
					cleaned := stripVertexIncompatibleFields(raw)
					req.Body = io.NopCloser(bytes.NewReader(cleaned))
					req.ContentLength = int64(len(cleaned))
					req.Header.Del("Content-Length")
				} else {
					req.Body = io.NopCloser(bytes.NewReader(raw))
				}
			}
		},
	}

	log.Printf("vertex-bridge listening on %s -> %s%s", *listen, upstream.String(), prefix)
	if err := http.ListenAndServe(*listen, proxy); err != nil {
		log.Fatal(err)
	}
}
