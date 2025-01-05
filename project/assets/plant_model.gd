@tool
extends Node3D

@onready var plant_nodes: Array[Node3D] = [
	%Pot003,
	% "green dram",
	%Pot001,
	%Pot004,
	%Pot005,
	%Pot006,
	%Pot007,
	%Pot008,
	%Pot009,
	%Pot010,
]

enum Plant {
	TYPE_A,
	TYPE_B,
	TYPE_C,
	TYPE_D,
	TYPE_E, # agave
	TYPE_F, # haworthia_cooperi
	TYPE_G, # sedeveria
	TYPE_H, # crassula
	TYPE_I, # lithops
	TYPE_J, # senecio
}

@export var plant := Plant.TYPE_C:
	set(value):
		plant = value
		if not is_inside_tree(): return
		for node in plant_nodes:
			node.visible = false
		plant_nodes[plant].visible = true
