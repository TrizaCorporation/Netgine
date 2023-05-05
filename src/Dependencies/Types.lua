export type Middleware = {
    Inbound: {
        [number]: (...any) -> nil
    }?,
    Outbound: {
        [number]: (...any) -> nil
    }?,
    RateLimit: number
}

export type ConnectionCallback = (...any) -> any

return {}