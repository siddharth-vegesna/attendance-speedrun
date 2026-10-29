# All the jokes and tuning live here so anyone on the team can edit them
# without touching game code.
extends RefCounted

const ROOM_PREFIX := "B-"
const FIRST_ROOM := 201
const TIME_LIMIT := 60.0
const WRONG_ROOM_PENALTY := 7.0
const SHUFFLE_EVERY := 7.0
const QUIZ_TIME := 10.0
const BONK_CHANCE := 0.35

# "correct" is the index (0-3) of the right answer.
const QUESTIONS := [
	{"q": "How many times did the professor say \"basically\" last class?",
	 "a": ["3", "12", "47", "I was asleep"], "correct": 2},
	{"q": "What was the title of the last slide?",
	 "a": ["Conclusion", "Summary", "Thank You", "Any Questions? (No.)"], "correct": 2},
	{"q": "What happened with the projector last class?",
	 "a": ["Worked perfectly", "Took 15 minutes to connect to the laptop", "Displayed upside down", "Nothing, there is no projector"], "correct": 1},
	{"q": "Who answered the professor's question last class?",
	 "a": ["Everyone", "The same guy in the front row", "ChatGPT", "The professor, after 40 seconds of silence"], "correct": 1},
	{"q": "What did the professor say right before class ended?",
	 "a": ["Have a great day!", "We'll continue next class", "This WILL come in the exam", "You may leave early"], "correct": 2},
	{"q": "Which topic was covered last class?",
	 "a": ["The next chapter", "The same chapter, again", "Something not in the syllabus", "The class was cancelled. You'd know if you came."], "correct": 3},
	{"q": "What was written on the whiteboard when you walked in last class?",
	 "a": ["Today's agenda", "\"DO NOT ERASE\" from 2019", "A meme", "Nothing, the marker was dead"], "correct": 1},
]

# [speaker, line]. Speakers: "STUDENT" or "PROF".
const CUTSCENE := [
	["STUDENT", "SIR! Sorry I'm late! Can you please mark my attendance?"],
	["PROF", "Attendance? Hmm."],
	["PROF", "When I was young, we did roll call. It took too long."],
	["PROF", "Then we signed a sheet. Too long. Then QR codes. Then FACIAL RECOGNITION."],
	["PROF", "Now the camera marks you present before you even wake up. It is far too EASY."],
	["STUDENT", "...so can you mark me present?"],
	["PROF", "No. Go back to the main entrance."],
	["PROF", "You have 60 seconds to reach this classroom. Then you tell me what happened last class."],
	["STUDENT", "But sir, every classroom looks EXACTLY the same!"],
	["PROF", "Yes. Good luck."],
]

const GUIDE_LINES := [
	"Your class is on the roof. Probably.",
	"I have calculated the optimal route. Please turn around.",
	"Have you tried going left? No. The other left.",
	"Room numbers are a social construct.",
	"Fun fact: the stairs are optional if you believe in yourself.",
	"Your attendance is currently 74.99%. No pressure.",
	"I'd take the elevator. There is no elevator.",
	"Rooms are being re-optimized for your convenience.",
	"Based on your face, you are already absent.",
	"The professor locks the door at 60 seconds. I checked.",
]

const WRONG_ROOM_LINES := [
	"This is a Thermodynamics lab. You are not enrolled.",
	"Wrong room. 40 people just turned around to look at you.",
	"That was a quiz you weren't ready for. Leave.",
	"Wrong class. The professor has added you to his list anyway.",
	"Nope. That room has been B-something since 2007.",
	"Wrong room. Same desks though. They're always the same desks.",
]

const NPC_LINES := [
	"bro do you have notes from last class?",
	"is attendance today??",
	"which room is it again",
	"i heard the quiz got postponed (it didn't)",
	"bro the AC is broken again",
	"wait we had class today?",
	"just tell him you were in the washroom",
	"75% bro. 75%.",
]

const TIMEOUT_LINES := [
	"The door is locked. The professor can see you through the glass. He is smiling.",
	"Time's up. You have been marked absent by an AI that has never met you.",
	"60 seconds was a generous amount of time, according to the professor.",
]

const WRONG_ANSWER_LINES := [
	"Incorrect. Were you even in class? (Rhetorical. You weren't.)",
	"Wrong. The guy in the front row knew that.",
	"Interesting answer. Absent.",
]
