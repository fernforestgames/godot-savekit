## Generates a random v4 UUID string.
##
## Uses cryptographically secure random bytes via Crypto.generate_random_bytes().
## Returns a string in the format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
## where x is any hexadecimal digit and y is one of 8, 9, A, or B.
static func generate_uuid_v4() -> String:
    var crypto := Crypto.new()
    var bytes := crypto.generate_random_bytes(16)

    # Set version to 4 (bits 12-15 of the 7th byte)
    bytes[6] = (bytes[6] & 0x0f) | 0x40

    # Set variant to RFC 4122 (bits 6-7 of the 9th byte)
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    # Format as UUID string
    return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ]
