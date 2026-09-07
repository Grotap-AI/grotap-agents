---
id: "13934"
title: "Bug: platform — My Profile: Top right - Client Selection not loading  When first loading into ap"
complexity: medium
priority: normal
branch: "case-ded21caf-5900-4dcb-acf9-fb7dfde2bfab"
case_id: "ded21caf-5900-4dcb-acf9-fb7dfde2bfab"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "b17bbb36-c167-4a00-9ebd-2d53498f49b8"
team: "team5"
---

# Task: Bug: platform — My Profile: Top right - Client Selection not loading  When first loading into ap

## Context
My Profile: Top right - Client Selection not loading

When first loading into apps.grotap.com if I click on my profile Icon to see what companies I am connected to the load stalls for the first 3-5 seconds. This needs to be a clean and smooth load

[Narration] when I click on my profile icon in the top right after a hard refresh and load in the switch two company names do not load right away why is this taking so long
App: platform (platform)
Area: platform
Source: feedback_toolkit
Component: platform

## Requirements
[platform] My Profile: Top right - Client Selection not loading

When first loading into apps.grotap.com if I click on my profile Icon to see what companies I am connected to the load stalls for the first 3-5 seconds. This needs to be a clean and smooth load

[Narration] when I click on my profile icon in the top right after a hard refresh and load in the switch two company names do not load right away why is this taking so long

App: platform (platform)
Brand: Grotap Apps
Area of app: platform
Route: /apps/my-beta
Screen: apps
Session replay attached (rrweb, R2) (17806 ms): issue/75786935-40da-4500-86f8-800965b591ab/replay.json.gz
Narration audio attached (R2): issue/75786935-40da-4500-86f8-800965b591ab/narration.webm
Screenshots attached (R2): issue/75786935-40da-4500-86f8-800965b591ab/screenshot-1.png
Submitted by: mike.c@grotap.com via feedback toolkit

## User Narration
when I click on my profile icon in the top right after a hard refresh and load in the switch two company names do not load right away why is this taking so long

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "ded21caf-5900-4dcb-acf9-fb7dfde2bfab" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
