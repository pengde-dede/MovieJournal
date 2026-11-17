package io.github.pengde_dede.moviejournal.catalog;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

@Component
final class TrialAccess {
    record Session(String token, long expiresAt) {}
    private record Invite(String id, MinuteLimit limit) {}

    private static final Duration LIFETIME = Duration.ofDays(7);
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();
    private final byte[] secret;
    private final List<Invite> invites;
    private final Clock clock;
    private final MinuteLimit redemptionLimit = new MinuteLimit(60);
    private final MinuteLimit catalogLimit = new MinuteLimit(300);

    @Autowired
    TrialAccess(@Value("${MOVIEJOURNAL_TRIAL_SECRET:}") String secret,
                @Value("${MOVIEJOURNAL_TRIAL_INVITES:}") String invitations) {
        this(secret, invitations, Clock.systemUTC());
    }

    TrialAccess(String secret, String invitations, Clock clock) {
        if (secret.length() < 32) throw new IllegalArgumentException("Configure a random trial signing secret.");
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.clock = clock;
        var configured = new ArrayList<Invite>();
        for (String raw : invitations.split(",")) {
            String code = raw.strip();
            if (!isCode(code)) throw new IllegalArgumentException("Configure trial invitation codes (16–96 URL-safe characters).");
            String id = signature("invite:" + code);
            if (configured.stream().noneMatch(existing -> existing.id().equals(id))) {
                configured.add(new Invite(id, new MinuteLimit(100)));
            }
        }
        if (configured.isEmpty()) throw new IllegalArgumentException("Configure at least one trial invitation code.");
        invites = List.copyOf(configured);
    }

    Session exchange(String input) {
        long now = clock.instant().getEpochSecond();
        redemptionLimit.consume(now);
        String code = input == null ? "" : input.strip();
        if (!isCode(code)) throw unauthorized();
        String id = signature("invite:" + code);
        findInvite(id);
        long expiry = now + LIFETIME.toSeconds();
        String payload = expiry + "." + id;
        return new Session(payload + "." + signature("session:" + payload), expiry);
    }

    void authorize(String authorization) {
        if (authorization == null || authorization.length() > 180 || !authorization.startsWith("Bearer ")) {
            throw unauthorized();
        }
        String token = authorization.substring(7);
        String[] parts = token.split("\\.", -1);
        if (parts.length != 3 || !constantEquals(signature("session:" + parts[0] + "." + parts[1]), parts[2])) {
            throw unauthorized();
        }
        long expiry;
        try {
            expiry = Long.parseLong(parts[0]);
        } catch (NumberFormatException ex) {
            throw unauthorized();
        }
        long now = clock.instant().getEpochSecond();
        if (expiry <= now) throw unauthorized();
        findInvite(parts[1]).limit().consume(now);
        catalogLimit.consume(now);
    }

    private Invite findInvite(String id) {
        return invites.stream().filter(invite -> constantEquals(invite.id(), id)).findFirst()
            .orElseThrow(TrialAccess::unauthorized);
    }

    private String signature(String payload) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            return ENCODER.encodeToString(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
        } catch (GeneralSecurityException ex) {
            throw new IllegalStateException("Cannot initialize trial authentication.", ex);
        }
    }

    private static boolean isCode(String code) {
        return code.length() >= 16 && code.length() <= 96 && code.matches("[A-Za-z0-9_-]+");
    }

    private static boolean constantEquals(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }

    private static ResponseStatusException unauthorized() {
        return new ResponseStatusException(HttpStatus.UNAUTHORIZED);
    }

    private static final class MinuteLimit {
        private final int maximum;
        private long minute = Long.MIN_VALUE;
        private int used;

        MinuteLimit(int maximum) { this.maximum = maximum; }

        synchronized void consume(long now) {
            long currentMinute = now / 60;
            if (currentMinute != minute) {
                minute = currentMinute;
                used = 0;
            }
            if (used >= maximum) throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS);
            used++;
        }
    }
}
