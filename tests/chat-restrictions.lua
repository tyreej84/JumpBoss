local Harness = dofile("tests/harness.lua")
local function check(value, message) if not value then error(message) end end

local function scenario(state, blockOnce)
    local harness = Harness.new({ addonPath = "JumpBoss.lua", groupMode = "RAID", throttleMax = 10 })
    local client = harness:createClient({ name = "Alice", classFile = "MAGE" })
    client:loadAddon()
    client:fireEvent("ENCOUNTER_START", 301, "Restriction Boss")
    harness:advance(0.5)
    client:fireEvent("PLAYER_JUMP")
    client.chatRestrictionState = state
    client.blockNextChat = blockOnce
    client:fireEvent("ENCOUNTER_END", 301, "Restriction Boss", 16, 1, 1)
    harness:advance(25)
    if state ~= 0 then
        check((client.chatAttempts or 0) == 0, "Restricted chat API was called outside combat")
        check(#client.chatLog == 0, "Posted while chat restricted")
        client.chatRestrictionState = 0
        harness:advance(25)
    end
    check(#client.chatLog == 2, "Expected exactly a header and winner line after restrictions clear")
    check(client.chatLog[1].message:find("Jump Leaderboard", 1, true), "Header was lost during retry")
    check(client.chatLog[2].message:find("Alice", 1, true), "Winner was lost during retry")
    check(client.chatAttempts == (blockOnce and 3 or 2), "Unexpected retries or duplicate sends")
end

scenario(2, false)
scenario(1, false)
scenario(0, true)
print("PASS: chat Active/Activating gates and blocked-call queue preservation")
