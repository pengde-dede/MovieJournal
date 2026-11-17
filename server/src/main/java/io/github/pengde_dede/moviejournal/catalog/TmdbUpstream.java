package io.github.pengde_dede.moviejournal.catalog;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.util.UriComponentsBuilder;

@Component
class TmdbUpstream {
    private final HttpClient client;
    private final URI origin;
    private final String key;

    @Autowired
    TmdbUpstream(@Value("${TMDB_API_KEY:}") String key,
                 @Value("${TMDB_API_HOST:api.themoviedb.org}") String host) {
        this(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(4)).build(),
            upstreamOrigin(host), key);
    }

    private static URI upstreamOrigin(String host) {
        return switch (host) {
            case "api.themoviedb.org", "api.tmdb.org" -> URI.create("https://" + host);
            default -> throw new IllegalArgumentException("Configure a supported TMDB API hostname.");
        };
    }

    TmdbUpstream(HttpClient client, URI origin, String key) {
        if (key.isBlank()) throw new IllegalArgumentException("Configure the TMDB API key in the server environment.");
        this.client = client;
        this.origin = origin;
        this.key = key;
    }

    ResponseEntity<byte[]> get(String path, Map<String, String> query) {
        var values = new LinkedHashMap<>(query);
        values.put("api_key", key);
        var uri = UriComponentsBuilder.fromUri(origin).path(path);
        values.forEach((name, value) -> uri.queryParam(name, "{" + name + "}"));
        var request = HttpRequest.newBuilder(uri.encode().buildAndExpand(values).toUri())
            .timeout(Duration.ofSeconds(9)).header("Accept", "application/json").GET().build();
        try {
            var result = client.send(request, HttpResponse.BodyHandlers.ofByteArray());
            return switch (result.statusCode()) {
                case 200 -> ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(result.body());
                case 404 -> throw new ResponseStatusException(HttpStatus.NOT_FOUND);
                case 429 -> throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS);
                default -> throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
            };
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        } catch (IOException ex) {
            // Drop the upstream exception because its URL can include the key.
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
        }
    }
}
