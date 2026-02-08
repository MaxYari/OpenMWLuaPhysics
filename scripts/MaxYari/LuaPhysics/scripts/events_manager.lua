-- Author: ChatGPT 2024

-- Define the EventsManager class
EventsManager = {}
EventsManager.__index = EventsManager

-- Constructor for creating a new EventsManager instance
function EventsManager:new()
    local instance = setmetatable({}, self)
    instance.handlers = {}
    return instance
end

-- Method to add an event handler
function EventsManager:addEventHandler(callback)
    table.insert(self.handlers, callback)
end

-- Method to remove an event handler
function EventsManager:removeEventHandler(callback)
    for i, handler in ipairs(self.handlers) do
        if handler == callback then
            table.remove(self.handlers, i)
            break
        end
    end
end

-- Method to emit an event
function EventsManager:emit(...)
    for _, handler in ipairs(self.handlers) do
        handler(...)
    end
end

return EventsManager
