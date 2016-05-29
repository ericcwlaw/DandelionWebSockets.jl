using BufferedStreams

headers = Dict(
    # This is the expected response when the client sends
    # Sec-WebSocket-Key => "dGhlIHNhbXBsZSBub25jZQ=="
    "Sec-WebSocket-Accept" => "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
)

type MockRequest
    accept::ASCIIString

    uri::Requests.URI
    method::ASCIIString
    headers::Dict


    MockRequest(accept::ASCIIString) = new(accept, Requests.URI("http://some/uri"),
        ascii("method"), Dict())
end

type FakeResponseStream
    socket::IO
end

function mock_do_stream_request(m::MockRequest, uri::Requests.URI, method::ASCIIString;
    headers=Dict(),
    tls_conf=Requests.TLS_VERIFY)

    m.uri = uri
    m.method = method
    m.headers = headers

    FakeResponseStream(IOBuffer())
end

facts("Handshake") do
    context("Validation") do
        stream = IOBuffer()
        ok_handshake = DandelionWebSockets.HandshakeResult(
            "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
            stream,
            headers,
            [])

        bad_handshake = DandelionWebSockets.HandshakeResult(
            "notagoodreply",
            stream,
            headers,
            [])

        missing_header = DandelionWebSockets.HandshakeResult(
            "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
            stream,
            Dict(),
            [])

        @fact ok_handshake --> DandelionWebSockets.validate
        @fact bad_handshake --> x -> !DandelionWebSockets.validate(x)
        @fact missing_header --> x -> !DandelionWebSockets.validate(x)
    end

    context("Handshake calculations") do
        rng = FakeRNG{UInt8}(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10")
        actual_key = DandelionWebSockets.make_websocket_key(rng)
        @fact actual_key --> ascii("AQIDBAUGBwgJCgsMDQ4PEA==")

        key = ascii("dGhlIHNhbXBsZSBub25jZQ==")
        @fact DandelionWebSockets.calculate_accept(key) --> "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    end

    context("Make headers") do
        rng = FakeRNG{UInt8}(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10")
        key = DandelionWebSockets.make_websocket_key(rng)

        headers = DandelionWebSockets.make_headers(key)
        @fact headers["Sec-WebSocket-Key"] --> key
        @fact headers["Upgrade"] --> "websocket"
        @fact headers["Connection"] --> "Upgrade"
        @fact headers["Sec-WebSocket-Version"] --> "13"
    end

    context("Handshake") do
        rng = FakeRNG{UInt8}(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10")
        key = ascii("AQIDBAUGBwgJCgsMDQ4PEA==")
        expected_headers = DandelionWebSockets.make_headers(key)

        expected_accept = DandelionWebSockets.calculate_accept(key)

        uri = Requests.URI("http://localhost:8000")

        m = MockRequest(expected_accept)
        function do_req(uri::Requests.URI, method::ASCIIString; headers=Dict())
            mock_do_stream_request(m, uri, method; headers=headers)
        end

        handshake_result = DandelionWebSockets.do_handshake(rng, uri; do_request=do_req)

        @fact m.method --> ascii("GET")
        @fact m.uri --> uri
        @fact m.headers --> expected_headers

        @fact handshake_result.expected_accept --> expected_accept
    end

    context("Convert URIs from ws to http") do
        ws_uri = Requests.URI("ws://some/uri")
        wss_uri = Requests.URI("wss://some/uri")
        http_uri = Requests.URI("http://some/uri")
        @fact DandelionWebSockets.convert_ws_uri(ws_uri) --> Requests.URI("http://some/uri")
        @fact DandelionWebSockets.convert_ws_uri(wss_uri) --> Requests.URI("https://some/uri")
        @fact DandelionWebSockets.convert_ws_uri(http_uri) --> http_uri
    end

    context("SSL handshakes result in a BufferedInputStream stream") do
        rng = FakeRNG{UInt8}(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10")
        key = ascii("AQIDBAUGBwgJCgsMDQ4PEA==")
        expected_accept = DandelionWebSockets.calculate_accept(key)

        uri = Requests.URI("http://localhost:8000")
        ssl_uri = Requests.URI("https://localhost:8000")

        m = MockRequest(expected_accept)
        do_req(uri::Requests.URI, method::ASCIIString; headers=Dict()) =
            mock_do_stream_request(m, uri, method; headers=headers)

        normal_handshake_result = DandelionWebSockets.do_handshake(rng, uri; do_request=do_req)
        @fact isa(normal_handshake_result.stream, BufferedInputStream) --> false

        rng = FakeRNG{UInt8}(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10")
        ssl_handshake_result = DandelionWebSockets.do_handshake(rng, ssl_uri, do_request=do_req)
        @fact isa(ssl_handshake_result.stream, BufferedInputStream) --> true
    end
end

