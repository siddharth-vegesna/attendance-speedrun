# All the jokes and tuning live here so anyone on the team can edit them
# without touching game code.
extends RefCounted

const ROOM_PREFIX := "B-"
const FIRST_ROOM := 201
const TIME_LIMIT := 60.0
const WRONG_ROOM_PENALTY := 7.0
const SHUFFLE_EVERY := 7.0
const QUIZ_TIME := 15.0
const MIN_ATTENDANCE := 60.0     # BITS rule: below this you are debarred
const BONK_CHANCE := 0.0       # doors that slam into you (0 = off)
const SHUFFLE_ROOMS := false    # room signs re-shuffling during the run

# Pick-a-subject questions. "correct" is the index (0-3) of the right answer.
# The first six are real courses; the rest are for people who don't want to be tested.
const SUBJECTS := {
	"Digital Design": [
		{"q": "An AND gate outputs 1 when...", "a": ["Any input is 1", "All inputs are 1", "All inputs are 0", "It feels like it"], "correct": 1},
		{"q": "Main difference between a latch and a flip-flop?", "a": ["Latch is level-triggered, flip-flop is edge-triggered", "Flip-flops are cheaper", "Latches only exist in Java", "No difference, just vibes"], "correct": 0},
		{"q": "How many bits does one flip-flop store?", "a": ["1", "2", "8", "Depends on the professor's mood"], "correct": 0},
		{"q": "Which of these is a universal gate?", "a": ["XOR", "NAND", "AND", "The main gate"], "correct": 1},
		{"q": "What is binary 1010 in decimal?", "a": ["8", "10", "12", "1010"], "correct": 1},
	],
	"Logic in CS": [
		{"q": "\"It is raining AND I am in class\" is an example of...", "a": ["Propositional logic", "Temporal logic", "Fuzzy logic", "Wishful thinking"], "correct": 0},
		{"q": "Which logic uses quantifiers like \"for all\" and \"there exists\"?", "a": ["Propositional logic", "Predicate (first-order) logic", "Boolean algebra", "Attendance logic"], "correct": 1},
		{"q": "\"Eventually, the student will attend class\" needs which logic?", "a": ["Propositional", "Predicate", "Temporal", "None. It will never happen."], "correct": 2},
		{"q": "p -> q is FALSE only when...", "a": ["p is true and q is false", "p is false and q is true", "both are false", "both are true"], "correct": 0},
	],
	"Discrete Maths": [
		{"q": "A poset (partially ordered set) relation must be...", "a": ["Reflexive, antisymmetric, transitive", "Reflexive, symmetric, transitive", "Only transitive", "Ordered from the Minimart"], "correct": 0},
		{"q": "An equivalence relation must be...", "a": ["Reflexive, antisymmetric, transitive", "Reflexive, symmetric, transitive", "Irreflexive and symmetric", "Equally confusing"], "correct": 1},
		{"q": "How many subsets does a set with 3 elements have?", "a": ["3", "6", "8", "9"], "correct": 2},
		{"q": "Which of these is NOT a valid proof technique?", "a": ["Induction", "Contradiction", "Contrapositive", "Trust me bro"], "correct": 3},
	],
	"OOP": [
		{"q": "Which is NOT one of the 4 pillars of OOP?", "a": ["Encapsulation", "Inheritance", "Polymorphism", "Compilation"], "correct": 3},
		{"q": "Method overloading means...", "a": ["Same name, different parameters", "A method that does too much", "Same signature redefined in a subclass", "Calling it during exams"], "correct": 0},
		{"q": "A class is to an object as...", "a": ["A blueprint is to a house", "A house is to a blueprint", "Java is to coffee", "Attendance is to me"], "correct": 0},
		{"q": "Which keyword creates an object in Java?", "a": ["class", "new", "this", "make"], "correct": 1},
	],
	"C Programming": [
		{"q": "What does printf(\"%d\", 5 / 2); print?", "a": ["2.5", "2", "3", "Segmentation fault"], "correct": 1},
		{"q": "Which operator gives you the address of a variable?", "a": ["*", "&", "#", "@"], "correct": 1},
		{"q": "Arrays in C start at index...", "a": ["0", "1", "-1", "Whatever malloc feels like"], "correct": 0},
		{"q": "A missing semicolon gives you a...", "a": ["Runtime error", "Compile error", "Warning, it's fine", "Free pass"], "correct": 1},
	],
	"Economics": [
		{"q": "When price goes up, quantity demanded usually...", "a": ["Goes up", "Goes down", "Stays the same", "Leaves the chat"], "correct": 1},
		{"q": "Opportunity cost is...", "a": ["The value of the next best option you gave up", "The price on the tag", "The cost of missing an opportunity to sleep", "Always zero"], "correct": 0},
		{"q": "Supply increases, demand stays the same. Price...", "a": ["Rises", "Falls", "Stays the same", "Becomes 60%"], "correct": 1},
		{"q": "Trade happens because of...", "a": ["Comparative advantage", "Absolute boredom", "Inflation only", "The Minimart running out"], "correct": 0},
	],
	"Attendance Studies": [
		{"q": "What is the minimum attendance at BITS?", "a": ["50%", "60%", "75%", "Vibes"], "correct": 1},
		{"q": "Your attendance is 59.99%. The admin will...", "a": ["Round it up", "Debar you", "Give you a hug", "Not notice"], "correct": 1},
		{"q": "Best excuse for being late?", "a": ["Traffic", "The lift", "\"Sir, the door hit me\"", "Honesty"], "correct": 2},
	],
	"Advanced Napping": [
		{"q": "Optimal nap spot in a lecture hall?", "a": ["Front row", "Back row, behind the tall guy", "On the professor's desk", "The projector"], "correct": 1},
		{"q": "How long is a power nap?", "a": ["20 minutes", "2 hours", "The whole semester", "Until the bell"], "correct": 0},
		{"q": "The professor asks you a question mid-nap. You say...", "a": ["\"Can you repeat that?\"", "\"The answer is 42\"", "\"I agree with the previous speaker\"", "Nothing. You're asleep."], "correct": 2},
	],
}

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
	"Your attendance is currently 59.99%. No pressure.",
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
	"the minimart ran out of the good chips AGAIN",
	"bro who took my charger",
	"is the wifi down or is it just me",
	"i swear this staircase gets longer every day",
	"anyone want to split a shawarma",
	"the AC on the first floor is set to antarctica",
	"i have a quiz in 10 mins and i know nothing",
	"why is there a vending machine if it never works",
	"ok but who keeps moving the room numbers",
	"bro i only came for the free food",
	"59.99%. they debarred me for 0.01%.",
	"did you see that guy get hit by a door",
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
