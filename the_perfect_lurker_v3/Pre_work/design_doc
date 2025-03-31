# Game Design Document: The Perfect Lurker - The Game

## Overview
**The Perfect Lurker** is a Twitch and potentially YouTube-based interactive game designed for stream viewers who engage by watching but not chatting. The game rewards users for their silence by allowing them to progress in a race around a looping track. The first player to join and remain silent the longest typically wins.

The purpose of the game is to help streamers maintain viewership and increase engagement metrics without requiring active chat participation, which can help boost a channel’s ranking and monetization potential.

## Platform & Engine
- **Engine:** Godot (fully implemented in Godot, moving away from the previous Python backend)
- **Platforms:** Twitch (Primary), YouTube (Secondary - subject to feasibility)

## Gameplay Flow
### Twitch Integration
1. **Joining the Race:**
   - Viewers join by redeeming a channel point reward, which acts as consent to participate.
   - Only users who opt-in via channel points are entered into the race.
   - !leave will remove users from race and all current tracking metrics
    (for example 1st place leaving will, cause an new 1st place )

2. **Race Mechanics:**
   - Every 10 seconds of silence earns the user **1 point** and moves them forward **1 game space**.
   - Speaking in chat results in a **loss of 1 point** and moving **1 space backward**.
   - Participants cannot go below **0 points**.

3. **Race Progression:**
   - A bot scans chat activity every 10 seconds to update the leaderboard.
   - Completing a full lap (10 minutes of silence) is recorded.
   - The race continues until the streamer issues the command **!finallurker**.
   - At the end, rankings are displayed:
     - **Top 3 players by points**
     - **Total laps completed by each player**
     - **Overall leaderboard of all races**

4. **Game Restart:**
   - After a race ends, the game resets upon reopening.
   - If the system crashes, we want to recall the last game and all data to finish the race properly with **!finallurker**

### YouTube Integration (Potential)
- Users may enter the race with **commands** (e.g., `!joinrace`, `!leave`).
- YouTube’s chat structure may not allow seamless tracking like Twitch.
- Requires research on feasible API integration.

## Special Events & Traps
### Traps (Power-Ups & Power-Downs)
- **Yellow Trap:**
  - Dropped behind a player’s current position.
  - Can hit anyone, including the player who dropped it.
  - Triggered if a user talks or laps back onto it.
  
- **Red Trap:**
  - Targets the player directly in front.
  - Moves as if both players are on the same lap (prevents excessive travel time).

- **Green Trap (TBA):**
  - Randomly selects a target ahead or behind.
  - Has a **50/50 chance** to hit or miss.

- **Blue Trap:**
  - Moves forward, attempting to hit multiple players.
  - Has a **40/60 chance** of hitting users between the thrower and 1st place.
  - Becomes **50/50 chance** within the top 5.
  - **1st place is guaranteed to be hit**, triggering a major stage shake-up.
  - Possible level change


### Defensive & Speed Boosts
- **Shields:**
  - Can absorb up to **3 trap hits**.
- **Boosts:**
  - Reduces **1 minute from a 10-minute lap time**.
  - Shortcut channel point you can hold and use to take short cut.
    if you are hit or use it in the wrong place you lose.

## Technical Considerations
- **Chat Integration:**
  - Twitch IRC bot to monitor chat activity and track viewers.
  - Requires handling API limits and message parsing.
- **YouTube Challenges:**
  - No direct IRC-style viewer list.
  - Requires API polling or alternative tracking methods.
- **Game Persistence:**
  - Saving leaderboards and stats between sessions.

## Potential Issues & Considerations
1. **Bot Detection by Twitch/YouTube:**
   - Ensure that interactions comply with platform guidelines.
   - Avoid excessive API calls.
2. **Latency & Timing Issues:**
   - Chat scanning might cause slight delays in movement updates.
3. **Exploits & Cheating Prevention:**
   - Ensure traps and movement calculations are fair.
   - Implement flood protection to prevent message spam exploits.
   - Users cant use traps until they have 5 points, cant move behind starting line 

## Future Enhancements
- Expand with additional power-ups and modifiers.
- Implement dynamic track changes.
- Introduce team-based modes or cooperative elements collab streams.
- data collection 


## 