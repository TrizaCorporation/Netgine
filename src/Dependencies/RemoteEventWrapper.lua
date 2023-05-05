local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Types = require(script.Parent.Types)
local EnumHelper = require(script.Parent.EnumHelper)
local Connection = require(script.Parent.Connection)
local Promise = require(script.Parent.Parent.Packages.Promise)

local RequestType = EnumHelper:MakeEnum("RemoteEventWrapper.RequestType", {
    "Outbound",
    "Inbound"
})

local RemoteEventWrapper = {}
RemoteEventWrapper.__index = RemoteEventWrapper

function RemoteEventWrapper:Wrap(event: RemoteEvent, middleware: Types.Middleware?)
    local self = setmetatable({}, RemoteEventWrapper)
    
    self.Middleware = middleware
    self.Event = event or Instance.new("RemoteEvent")
    self._environment = RunService:IsServer() and "Server" or "Client"
    self._connections = {}

    self.Event[self._environment == "Server" and "OnServerEvent" or "OnClientEvent"]:Connect(function(...)
        self:HandleRequest(RequestType.Inbound, ...)
    end)

    return self
end

function RemoteEventWrapper:Connect(callback: Types.ConnectionCallback)
    local CreatedConnection = Connection.new(callback)
    table.insert(self._connections, CreatedConnection)
end

function RemoteEventWrapper:HandleRequest(type: EnumItem, ...)
    local Args = {...}
    table.insert(Args, 1, self.Event.Name)
    local Middleware = self.Middleware :: Types.Middleware
    if type == RequestType.Outbound then
        if Middleware and Middleware.Outbound then
            for _, callback in Middleware.Outbound do
                task.spawn(callback, table.unpack(Args))
            end
        end
    elseif type == RequestType.Inbound then
        if Middleware and Middleware.Inbound then
            for _, callback in Middleware.Inbound do
                task.spawn(callback, table.unpack(Args))
            end
        end

        for i, connection in self._connections do
            if connection._callback then
                task.spawn(connection._callback, ...)
            else
                table.remove(self._connections, i)
            end
        end
    end
end

function RemoteEventWrapper:Fire(...)
    if self._environment == "Client" then
        self:HandleRequest(RequestType.Outbound, ...)
        self.Event:FireServer(...)
    elseif self._environment == "Server" then
        self:HandleRequest(RequestType.Outbound, ...)
        self.Event:FireClient(...)
    end
end

function RemoteEventWrapper:FireGroup(group: {[number]: Player}, ...)
    assert(self._environment == "Server", "RemoteEventWrapper:FireGroup() can only be called on the server.")
    local Args = {...}
    local ClonedArgs = table.clone(Args)

    table.insert(ClonedArgs, 1, group)

    local FirePromises = {}

    for _, GroupPlayer in group do
        table.insert(FirePromises, Promise.new(function(resolve)
            self.Event:FireClient(GroupPlayer, table.unpack(Args))
            resolve()
        end))
    end

    self:HandleRequest(RequestType.Outbound, table.unpack(ClonedArgs))

    Promise.all(FirePromises):await()
end

function RemoteEventWrapper:FireFilter(filter: (player: Player) -> boolean, ...)
    assert(self._environment == "Server", "RemoteEventWrapper:FireFilter() can only be called on the server.")
    local Args = {...}
    local ClonedArgs = table.clone(Args)

    local ValidPlayers: {[number]: Player}

    for _, player in Players:GetPlayers() do
        if filter(player) then
            table.insert(ValidPlayers, player)
        end
    end

    table.insert(ClonedArgs, 1, ValidPlayers)

    local FirePromises = {}

    for _, ValidPlayer in ValidPlayers do
        table.insert(FirePromises, Promise.new(function(resolve)
            self.Event:FireClient(ValidPlayer, table.unpack(Args))
            resolve()
        end))
    end

    self:HandleRequest(RequestType.Outbound, table.unpack(ClonedArgs))

    Promise.all(FirePromises):await()
end

return RemoteEventWrapper