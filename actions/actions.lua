local guard = require("meido.guard")

local actions = {}

-- [action constructors]

actions.simple_tween = function(prop, initial, final, mapper)
    guard.non_nil("prop", prop)
    guard.can_add("initial", initial)
    guard.can_sub("final", final)

    local change = final - initial

    if mapper then
        guard.callable("mapper", mapper)
        return function(time, env)
            env[prop] = mapper(initial + change * time)
        end
    else
        return function(time, env)
            env[prop] = initial + change * time
        end
    end
end

actions.simple_custom_tween = function(initial, final, callback)
    guard.can_add("initial", initial)
    guard.can_sub("final", final)
    guard.callable("callback", callback)
    
    local change = final - initial
    return function(time, env)
        return callback(env, initial + change * time)
    end
end

actions.tween = function(prop, initial, final, easing_func, mapper)
    guard.non_nil("prop", prop)
    guard.can_add("initial", initial)
    guard.can_sub("final", final)
    guard.callable("easing_func", easing_func)

    local change = final - initial

    if mapper then
        guard.callable("mapper", mapper)
        return function(time, env)
            env[prop] =
                mapper(easing_func(time, initial, change))
        end
    else
        return function(time, env)
            env[prop] =
                easing_func(time, initial, change)
        end
    end
end

actions.custom_tween = function(initial, final, easing_func, callback)
    guard.can_add("initial", initial)
    guard.can_sub("final", final)
    guard.callable("easing_func", easing_func)
    guard.callable("callback", callback)
    
    local change = final - initial
    return function(time, env)
        return callback(env, easing_func(time, initial, change))
    end
end

actions.event = function(callback)
    guard.callable("callback", callback)

    local last_time
    return function(time, env)
        if last_time ~= time then
            last_time = time
            if time == 1 then
                return callback(env)
            end
        end
    end
end

-- [action combinators]

actions.reverse = function(action)
    guard.callable("action", action)

    return function(time, env)
        return action(1 - time, env)
    end
end

actions.ease = function(easing_func, action)
    guard.callable("easing_func", easing_func)
    guard.callable("action", action)

    return function(time, env)
        return action(easing_func(time, 0, 1), env)
    end
end

actions.combine = function(...)
    local count = select("#", ...)

    for i = 1, count do
        local t = ...
        guard.callable("action", t)
    end

    if count == 1 then
        return select(1, ...)
    elseif count == 2 then
        local t1, t2 = ...
        return function(time, env)
            t1(time, env)
            t2(time, env)
        end
    elseif count == 3 then
        local t1, t2, t3 = ...
        return function(time, env)
            t1(time, env)
            t2(time, env)
            t3(time, env)
        end
    elseif count == 4 then
        local t1, t2, t3, t4 = ...
        return function(time, env)
            t1(time, env)
            t2(time, env)
            t3(time, env)
            t4(time, env)
        end
    else
        local actions = {...}
        return function(time, env)
            for i = 1, #acitons do
                actions[i](time, env)
            end
        end
    end
end

actions.cross = function(action1, action2)
    guard.callable("action1", action1)
    guard.callable("action2", action2)

    return function(time, env)
        action1(1 - time, env)
        action2(time, env)
    end
end

actions.map_time = function(time_var_or_func, action)
    guard.callable("action", action)

    local t = type(time_var_or_func)
    if t == "string" then
        return function(time, env)
            return action(env[time_var_or_func], env)
        end
    else
        guard.callable("mapper", time_var_or_func)
        return function(time, env)
            return action(time_var_or_func(time), env)
        end
    end
end

return actions