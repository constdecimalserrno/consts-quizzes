# Plan

Take a look at /Users/constdecimalserrno/Documents/Tabletop/Games/quiz  I want to make it into an always running online version - that anyone can visit at anytime, and just answer triva questions.

It should be a flutter app ( both ios and web ), with firsbase as a backend/hosting/auth/functions ( you have full control and can create a porject under const.decimals.errno@gmail.com

It should constantly run a game of 20 questions. As questions go on, they get harder, and the theme/category is randomized per game

It should look like a fun 90s game show, use /frontend-design skill to do it

Signing in is not nesseacy - people can just come an answer questions - they will be signed in as anynonmous ( firebase auth ), and we'll have a "reaper" firebase function that checks all users/documets and remove anyone that has not been active for 90 days ( X days, in firebase there should be a admin app-config document). They always have the option to save their progress by signing in with google apple or twitter. 

Like in user-picks ( /Users/constdecimalserrno/Documents/Tabletop/Mitch/user-picks ) users can connext their twitter and import their banner/pfp/name - otherwise use the same handle generation user picks does  

Note the same app-level config in firebase should also control how mnay questions per game, timings, points, etc. 
