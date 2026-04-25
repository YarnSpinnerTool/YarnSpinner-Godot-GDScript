extends CharacterBody3D

@export var speed = 1

func _input(_event: InputEvent) -> void:
	# var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# velocity = Vector3(input.x, 0, input.y) * speed;
	pass

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	move_and_slide()
	
	pass
