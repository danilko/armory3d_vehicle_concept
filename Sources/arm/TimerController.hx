package arm;

import armory.trait.physics.RigidBody;
import iron.Trait;
import iron.object.Object;
import iron.system.Time;

import armory.trait.physics.PhysicsWorld;
import armory.trait.internal.CanvasScript;

#if arm_bullet
import haxebullet.Bullet;
#end

class TimerController extends iron.Trait {
	private var startTime:Float;
	private var endTime:Float;
	private var bestDeltaTime:Float;
	private var currentDeltaTime:Float;
	private var physics:PhysicsWorld;
	private var contact_cont:Int;

	private var previousContact:Bool;
	private var isTimerStart:Bool;

	private function triggerTimer()
	{
		if(! isTimerStart)
		{
			isTimerStart = true;
			startTime = Time.realTime();
		}
		else
		{
			isTimerStart = false;
		}
	}

	private function updateTimer()
	{
		currentDeltaTime = Time.realTime() - startTime;
	}

	private function formulateTimeStamp(time:Float):String
	{
		if(time < 0) return "--";

		var returnString = "" + time;

		if (returnString.length == 1)
		{
			returnString = "0" + time;
		}

		return returnString;
	}

	private function generateTimeStampString(time:Float):String
	{
		if(time < 0) return "--:--:--:--";

		var miniseconds = Math.round(time * 100);

		var hour = 0;
		if (miniseconds >= 360000) {
			hour = Std.int(miniseconds/360000);
			miniseconds = miniseconds -  (hour * 360000);
		}
		
		var minutes =  0;
		if (miniseconds >= 6000) {
			minutes = Std.int(miniseconds/6000);
			miniseconds = miniseconds -  (minutes * 6000);
		}

		var seconds =  0;
	
		if (miniseconds >= 100) {
			seconds = Std.int(miniseconds/100);
			miniseconds = miniseconds -  (seconds * 100);
		}
		
		var hourString = formulateTimeStamp(hour);
		var minuteString = formulateTimeStamp(minutes);
		var secondString = formulateTimeStamp(seconds);
		var	miniSecondString = formulateTimeStamp(miniseconds);

		return hourString + ":" + minuteString + ":" + secondString + ":" + miniSecondString;
	}


	public function new() {
		super();
		iron.Scene.active.getTrait(CanvasScript).getElement("text_previous_lap_timer").text = generateTimeStampString(-1);
		iron.Scene.active.getTrait(CanvasScript).getElement("text_current_lap_timer").text = generateTimeStampString(-1);


		 notifyOnInit(function() {
			physics = armory.trait.physics.PhysicsWorld.active;
            contact_cont = 0;
			previousContact = false;
		 });

		 notifyOnUpdate(function() {

			var rigidBodies = physics.getContacts(object.getTrait(RigidBody));
			
			var currentContact = false;
			if(rigidBodies != null){
				for (rigidBody in rigidBodies){
					if (rigidBody != null) {
						if (rigidBody.object.name == "Vehicle"){
							currentContact = true;
						}
					}
				}
			}

			// Only count during first contact
			if(previousContact == false && currentContact == true) {
				
				if (isTimerStart)
				{
					updateTimer();
					iron.Scene.active.getTrait(CanvasScript).getElement("text_previous_lap_timer").text = generateTimeStampString(currentDeltaTime);
					
					if ((bestDeltaTime == null) || (bestDeltaTime > currentDeltaTime))
					{
						bestDeltaTime = currentDeltaTime;
						iron.Scene.active.getTrait(CanvasScript).getElement("text_best_lap_timer").text = generateTimeStampString(bestDeltaTime);
					}

					// stop timer
					triggerTimer();
					// start timer
					triggerTimer();
				}
				else 
				{
					// start timer
					triggerTimer();
				}
			}

			previousContact = currentContact;

			if (isTimerStart)
			{
				updateTimer();
				iron.Scene.active.getTrait(CanvasScript).getElement("text_current_lap_timer").text =  generateTimeStampString(currentDeltaTime);
			}
		

			
		 });

		// notifyOnRemove(function() {
		// });
	}
}
