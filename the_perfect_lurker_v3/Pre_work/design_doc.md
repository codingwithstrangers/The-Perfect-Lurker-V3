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
   - !leave will remove users from the race and all current tracking metrics.
   - If the user leaves, the game adjusts the ranking (e.g., if the 1st place user leaves, a new 1st place will be assigned).

2. **Race Mechanics:**
   - Every 10 seconds, the game performs a **Check-In** to determine if the lurker is still actively viewing the stream.
     - If the lurker is **viewing**, they earn **1 point** and move forward **1 space** on the track.
     - If the lurker is **not viewing**, they **do not earn points** or progress.
     - This Check-In happens **before any points are awarded**.
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

4. **Focus Mode:**
   - After **10 minutes (600 seconds)** of continuous silent lurking, **Focus Mode** is activated.
     - In **Focus Mode**, the lurker earns **+0.5 speed per point** (they move forward faster for every point they earn).
   - Focus Mode is **disabled** if the lurker talks or loses points.
   - Focus Mode is **re-enabled** after 600 seconds of continuous lurking, and the lurker can earn **+0.5 speed** for every point.

5. **Game Restart:**
   - After a race ends, the game resets upon reopening.
   - If the system crashes, we want to recall the last game and all data to finish the race properly with **!finallurker**.

### YouTube Integration (Potential)
- Users may enter the race with **commands** (e.g., `!joinrace`, `!leave`).
- YouTube’s chat structure may not allow seamless tracking like Twitch.
- Requires research on feasible API integration.

---

## Special Events & Traps
### Talking Lurker Channel Point

- **Purpose:** The **Talking Lurker** Channel Point allows lurkers to talk in chat without incurring the typical penalties (loss of points or focus).
  
- **How it works:**
  - When the lurker uses the **Talking Lurker Channel Point**, they are allowed to talk in chat **without losing points** or moving backward in the race.
  - **Focus Mode is not disabled**, and the lurker continues to earn **points and speed** as usual during this time.
  - **Focus Mode** remains active while the **Talking Lurker Channel Point** is active, and no penalties are applied.
  - **No new points** are earned from talking, and **Focus Mode will not be enhanced** by talking.
  - After using the **Talking Lurker Channel Point**, the lurker’s race progress is unaffected by talking in chat, but they will still not gain additional points or focus unless they remain silent.

- **Limitations:**
  - The **Talking Lurker Channel Point** does not **add points** or **enhance Focus Mode**. It simply allows the lurker to chat without penalty for a limited time.
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
  - Shortcut channel point you can hold and use to take a shortcut.
    - If you are hit or use it in the wrong place, you lose.
   
### God Mode (Host Control)

- **Purpose:** **God Mode** grants the host ultimate control over the game, allowing them to directly modify points, player placements, and game mechanics in real-time. The changes made by the host are visible to all players, allowing for a dynamic experience that can shake up the race at any moment.

- **How it works:**
  - **Activate God Mode:** The host can activate **God Mode** using a specific command (e.g., `!godmode activate`).
  - Once activated, the host can:
    - **Remove or Add Points:** The host can **add or subtract points** from any player, instantly changing their position in the race. For example, if a player is in last place and the first place player has 100 points, the host can give the last place player 105 points, moving them to first. Points and placements are updated immediately.
    - **Attack or Defend:** The host can trigger **attack or defense** abilities on any player, impacting their progress and strategy in the race.
    - **Adjust Point Scaling:** The host can change how points are awarded, for example, by increasing the points awarded every 10 seconds or modifying how **Focus Mode** operates.
    - **Affect Placement:** The host can **move players up or down** the leaderboard, overriding the usual point system. A player’s position in the race can be adjusted with any point change, and point totals are updated accordingly.

- **Visibility and Impact:**
  - All changes made by the host are **immediately visible** to all players, so everyone can see when **God Mode** is active and understand how it’s influencing the race.
  - Players will see their points and placements change in real-time as the host manipulates the game.

- **Limitations and Considerations:**
  - Used to demo, give bonus, or used in jest and not to antagonize. 

---

## Technical Considerations
- **Chat Integration:**
  - Twitch IRC bot to monitor chat activity and track viewers.
  - Requires handling API limits and message parsing.
- **YouTube Challenges:**
  - No direct IRC-style viewer list.
  - Requires API polling or alternative tracking methods.
- **Game Persistence:**
  - Saving leaderboards and stats between sessions.

---

## Potential Issues & Considerations
1. **Bot Detection by Twitch/YouTube:**
   - Ensure that interactions comply with platform guidelines.
   - Avoid excessive API calls.
2. **Latency & Timing Issues:**
   - Chat scanning might cause slight delays in movement updates.
3. **Exploits & Cheating Prevention:**
   - Ensure traps and movement calculations are fair.
   - Implement flood protection to prevent message spam exploits.
   - Users can't use traps until they have 5 points, and can't move behind the starting line.

---

### Future Enhancements
- Expand with additional power-ups and modifiers.
- Implement dynamic track changes.
- Introduce team-based modes or cooperative elements for collab streams.
- Data collection.

---
