# 1.5.2 chat regression checks

From the checkout, run `lua tests/chat-restrictions.lua` and `lua tests/run-simulation.lua`.

The mock covers chat restrictions after personal combat, Activating/Active states, a blocked send that returns normally, winner-only posting, queue preservation, and addon-message throttling.

After installing, reload WoW and complete an encounter with two or more addon users. Confirm no leaderboard is sent while chat is restricted, the winner posts once when restrictions clear, and a fresh BugGrabber session has no new JumpBoss blocked-chat errors. Automatic posting must be enabled for this check. Test a key as well as a raid because restrictions can outlast individual encounters.

API evidence: Blizzard's [restriction API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua) and [restriction enums](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua) expose the Chat restriction and its Inactive, Activating, and Active states. Simulated success is not proof of delivery in the native client.
