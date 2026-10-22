"""class_name Incident
extends RefCounted

# Used to infer the type of incident
enum IncidentType 
{
	MEDICAL,
	FIRE,
	POLICE
}

var type: IncidentType					# Incident Type
var title: String						# Title of the incident
var description: String					# Incident description
var location: Vector2					# 2D location of the incident
var issued: float						# Start time that the incident occured
var elapsedActiveSeconds: float			# Tracks the time the incident has been active and unattended to
var lastUpdate: float					# Tracks last time data was updated - used to calculate progress between updates.
var isCrewAttending: bool				# Is the emergency crew attending this incident currently

func _init(type: IncidentType, title: String, decription: String, location: Vector2) -> void:
	type = type
	title = title
	description = description
	location = location
	issued = Time.get_ticks_msec() / 1000
	elapsedActiveSeconds = 0
	lastUpdate = issued
	isCrewAttending = false
	
"""
