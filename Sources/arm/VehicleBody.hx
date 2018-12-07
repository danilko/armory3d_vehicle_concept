package arm;

import iron.object.ParticleSystem;
import armory.trait.physics.RigidBody;
import iron.Trait;
import iron.object.Object;
import iron.object.CameraObject;
import iron.object.BoneAnimation;
import iron.object.Uniforms;
import iron.data.MaterialData;
import iron.object.Transform;
import iron.system.Time;
import iron.system.Input.Gamepad;
import iron.system.Input.Keyboard;

import armory.trait.physics.PhysicsWorld;
import armory.trait.internal.CanvasScript;
#if arm_bullet
import haxebullet.Bullet;
#end

class VehicleBody extends Trait {
	#if (!arm_bullet)
	public function new() {
		super();
	}
	#else
	var animation:BoneAnimation;
	var physics:PhysicsWorld;
	var transform:Transform;
	var camera:CameraObject;
	var state = 0;
	// Wheels
	var wheels:Array<Object> = [];
	var wheelNames:Array<String>;
	var vehicle:BtRaycastVehiclePointer = null;
	var carChassis:BtRigidBodyPointer;
	// Formula 1 Based https://en.wikipedia.org/wiki/Formula_One_car#Acceleration
	var chassis_mass = 1000.0;
	//var wheelFriction = 500;
	var wheelFriction = 10;
	var suspensionStiffness = 40.0;
	var suspensionDamping = 2.3;
	var suspensionCompression = 4.4;
	var suspensionRestLength = 0.3;
	var rollInfluence = 0.1;
	var transformDuration = false;
	
	var boostMode = false;
	var boostStartTime = 0.0;

	var MAX_SPEED=480;

	var boost0:ParticleSystem = null;
	var boost1:ParticleSystem = null;
	

    // km/h * 1h/60min * 1min/60sec * 1000m/km
	// 300 km/h in 4.8 sec (double the speed of F1)
	// https://en.wikipedia.org/wiki/Formula_One_car#Acceleration
	// 300 km/h * 1h/60min * 1min/60sec * 1000m/km * 1/4.8s = 17.4 m/s/s;
    var maxAcceleration = 17.4;

	var maxBreakingForce = 500.0;
	var breakState = false;
	var engineForce = 0.0;
	var breakingForce = 0.0;
	var vehicleSteering = 0.0;
	var steeringLimit = 0.15;
	var currentGear = 1;
	// This is factor contribute to engine rpm
	// 1000 rpm is about 128 km/h
	// set to 8000 to represent max possible speed of 1024 km/h
	var defaultEngineRPM = 8000.0;
	var startTime = 0.0;

	var keyboard:Keyboard = null;
	var gamepad:Gamepad = null;


	public function new(wheelName1:String, wheelName2:String, wheelName3:String, wheelName4:String, wheelName5:String, wheelName6:String) {
		super();

		wheelNames = [wheelName1, wheelName2, wheelName3, wheelName4, wheelName5, wheelName6];
		iron.Scene.active.notifyOnInit(init);
	}

	// Reference from https://www.patreon.com/posts/armory3d-blender-19362283
	function findAnimation(o:Object):BoneAnimation {
		if (o.animation != null) {
			return cast o.animation;
		}

		for (c in o.children) {
			var co = findAnimation(c);
			if (co != null)
				return co;
		} 

		return null;
	}

	function init() {
		keyboard = iron.system.Input.getKeyboard();
		gamepad = iron.system.Input.getGamepad(0);

		animation = findAnimation(object);
		physics = armory.trait.physics.PhysicsWorld.active;
		transform = object.transform;
		camera = iron.Scene.active.camera;

		for (n in wheelNames) {
			wheels.push(iron.Scene.active.root.getChild(n));
		}

		var wheelDirectionCS0 = BtVector3.create(0, 0, -1);
		var wheelAxleCS = BtVector3.create(1, 0, 0);

		var chassisShape = BtBoxShape.create(BtVector3.create(transform.dim.x / 2, transform.dim.y / 2, transform.dim.z / 2));

		var compound = BtCompoundShape.create();

		var localTrans = BtTransform.create();
		localTrans.setIdentity();
		// set to much lower value
		// https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=12112
		localTrans.setOrigin(BtVector3.create(0, 0, 1));

		compound.addChildShape(localTrans, chassisShape);

		carChassis = createRigidBody(chassis_mass, compound);

		// Create vehicle
		var tuning = BtVehicleTuning.create();
		var vehicleRayCaster = BtDefaultVehicleRaycaster.create(physics.world);
		vehicle = BtRaycastVehicle.create(tuning, carChassis, vehicleRayCaster);

		// Never deactivate the vehicle
		carChassis.setActivationState(BtCollisionObject.DISABLE_DEACTIVATION);

		// Choose coordinate system
		var rightIndex = 0;
		var upIndex = 2;
		var forwardIndex = 1;
		vehicle.setCoordinateSystem(rightIndex, upIndex, forwardIndex);

		// Add wheels
		for (i in 0...wheels.length) {
			var vehicleWheel = new VehicleWheel(i, wheels[i].transform, object.transform);

			vehicleWheel.isFrontWheel = true;
			if (i >= wheels.length - 2) {
				vehicleWheel.isFrontWheel = false;
			}

			vehicle.addWheel(vehicleWheel.getConnectionPoint(), wheelDirectionCS0, wheelAxleCS, suspensionRestLength, vehicleWheel.wheelRadius, tuning,
				vehicleWheel.isFrontWheel);
		}

		// Setup wheels
		for (i in 0...vehicle.getNumWheels()) {
			var wheel:BtWheelInfo = vehicle.getWheelInfo(i);
			wheel.m_suspensionStiffness = suspensionStiffness;
			wheel.m_wheelsDampingRelaxation = suspensionDamping;
			wheel.m_wheelsDampingCompression = suspensionCompression;
			wheel.m_frictionSlip = wheelFriction;
			if (i >= wheels.length - 2) {
				wheel.m_frictionSlip = wheelFriction * 0.8;
			}
			wheel.m_rollInfluence = rollInfluence;
		}
		
		// prevent vehicle from flip over, by limit the rotation  on forward axis
		// https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=8153
		carChassis.setAngularFactor(new BtVector3(0,0,1));

		physics.world.addAction(vehicle);

		animation.play("idle.circuit", null, 0.0, 1.0, false);
        transformDuration = false;

		notifyOnUpdate(update);

		// register material link callback
		Uniforms.externalFloatLinks.push(floatLink);

		var mo = cast(iron.Scene.active.root.getChild("model.boost0.particle"), iron.object.MeshObject);
        boost0 = mo.particleSystems.length > 0 ? mo.particleSystems[0] : null;
		if (boost0 == null) mo.particleOwner.particleSystems[0];
		boost0.disableLifetime();

		mo = cast(iron.Scene.active.root.getChild("model.boost1.particle"), iron.object.MeshObject);
        boost1 = mo.particleSystems.length > 0 ? mo.particleSystems[0] : null;
		if (boost1 == null) mo.particleOwner.particleSystems[0];
		boost1.disableLifetime();
	}

	function floatLink(object:Object, mat:MaterialData, link:String):Null<kha.FastFloat> {
		if (link == "Value") {
			if (breakState) {
				return 2;
			} else {
				return 0;
			}
			// var t = Time.time();
			// return Math.sin(t) * 0.5 + 0.5;
		}
		return null;
	}


	function stopWatchStart() {
		startTime = Time.realTime();
	}

	function stopWatchStop():Float {
		return Time.realTime() - startTime;
	}

	function update() {
		if (vehicle == null)
			return;
		
		var accel = 1.0;
		var steer = 1.0;

		var forward = keyboard.down("up");
		var left = keyboard.down("left");
		var right = keyboard.down("right");
		var brake = keyboard.down("down");
		var actionBoost = false;
		var actionTransform = false;

        if(gamepad != null)
        {
			if (Math.abs(gamepad.rightStick.x) > 0.1)
			{

			// steer = Math.abs(gamepad.rightStick.x);
		    if (gamepad.rightStick.x < 0.0)
			{
				left = true;
			}
			else if (gamepad.rightStick.x > 0.0)
			{
				right = true;
			}
			
			}

			if (gamepad.down("r2") > 0.0)
			{
				forward=true;
				accel=gamepad.down("r2");
				trace("accel " + accel);
			}
			else if (gamepad.down("l2") > 0.0)
			{
				brake = true;
			}

			actionTransform = gamepad.started("x");
			actionBoost = gamepad.started("o");
		}

		// check keyboard input one more time
		if (actionTransform == false)
		{
			actionTransform = keyboard.started("x");
		}
		
		if (actionBoost == false)
		{
			actionBoost = keyboard.started("s");
		}

		if (actionTransform) {
			// Only allow transfomration if boost is not enable
			if (boostMode == false)
			{
				transformDuration = true;

				if (state == 0) {
					state = state + 1;

					animation.play("transform.aero", null, 0.0, 1.0, false);
					MAX_SPEED=530;
					steeringLimit = 0.05;
				} else {
					state = 0;
					animation.play("transform.circuit", null, 0.0, 1.0, false);
					MAX_SPEED=480;
                    steeringLimit = 0.15;
				}
			}
		}

		if(actionBoost)
		{
			// only can boost in aero mode
			if(state == 1 && boostMode == false)
			{
				boostMode = true;
				MAX_SPEED=700;
				boostStartTime = Time.realTime();

				boost0.enableLifetime();
				boost1.enableLifetime();
			}
			// disable boost if is enable
			else if(boostMode == true)
			{
				boostMode = false;
				MAX_SPEED=530;

				boost0.disableLifetime();
				boost1.disableLifetime();
			}
		}

		if(boostMode)
		{
			var deltaBoosTime = Time.realTime() - boostStartTime;
			// Auto disable boost when time is up
			if(deltaBoosTime > 10) 
			{
				boostMode = false;
				MAX_SPEED=530;

				boost0.disableLifetime();
				boost1.disableLifetime();
			}
		}

		breakState = false;
		// var speed = Math.round(vehicle.getCurrentSpeedKmHour());
		// not using above as it seem the logic is around rigid body, so even when wheel is on air, seem to be slightl different
        var backendWheelInfo = vehicle.getWheelInfo(5);
		
		var speed = Math.round(((backendWheelInfo.m_deltaRotation / Time.step) * backendWheelInfo.m_wheelsRadius * 3.6));
		var displaySpeed = speed;
        if (displaySpeed == -1 || displaySpeed == 1)
		{
			displaySpeed = 0;
		}
		 iron.Scene.active.getTrait(CanvasScript).getElement("speed").text = "" + displaySpeed;
		
		if (forward) {
			if (speed < MAX_SPEED)
			{
			  engineForce = maxAcceleration * chassis_mass * accel;
			}
			else 
			{
			  engineForce = 0;
			}
			breakingForce = 0;
		//} else if (backward) {
		//	engineForce = -maxAcceleration * chassis_mass * accel;
		//	breakingForce = 0;
		//	breakState = true;
		} else if (brake) {
			//breakingForce = maxAcceleration * chassis_mass * accel;
            engineForce = 0;
			
			breakingForce = 100;
			breakState = true;
		} else {
			engineForce = 0;
			breakingForce = 20;
		}

		if (left) {
			if (vehicleSteering < steeringLimit)
				vehicleSteering += steer * 0.25 * Time.step;
		} else if (right) {
			if (vehicleSteering > (steeringLimit * -1))
				vehicleSteering -= steer * 0.25 * Time.step;
		} else if (vehicleSteering != 0) {
			var step = Math.abs(vehicleSteering) < Time.step ? Math.abs(vehicleSteering) : Time.step;
			if (vehicleSteering > 0)
				vehicleSteering -= step;
			else
				vehicleSteering += step;
		}

        //carChassis.applyCentralForce(new BtVector3(0,0,-1000));

		// iron.Scene.active.getTrait(CanvasScript).getElement("steering").text = "" + vehicleSteering;
		for (i in 0...vehicle.getNumWheels()) {

			// Try to capture before transform, but undefined/null for new properties
            var wheelInfo = vehicle.getWheelInfo(i);

			if (wheelInfo.m_bIsFrontWheel)
			{
                // Apply steering to the front wheels
			    vehicle.setSteeringValue(vehicleSteering, i);
			    //vehicle.applyEngineForce(engineForce, i);
			    vehicle.setBrake(breakingForce, i);
			}
			else 
			{
			    // Apply Engine Force and Break to two back - end wheel
		        vehicle.applyEngineForce(engineForce, i);
		        vehicle.setBrake(breakingForce, i);
		    }
			
			
				var wheelEffectController = object.getChild(wheelNames[i] + ".particle").getTrait(WheelController);
			if (brake == true && speed > 100)
			{
				wheelEffectController.isBrakeEffect = true;
			}
			else 
			{
				wheelEffectController.isBrakeEffect = false;
			}

			// Synchronize the wheels with the chassis worldtransform
			// update the second parameters to false to let the wheel stay at chasis
			vehicle.updateWheelTransform(i, false);
			// Update wheels transforms

			var trans = vehicle.getWheelTransformWS(i);
			var p = trans.getOrigin();
			var q = trans.getRotation();
			wheels[i].transform.localOnly = true;
			wheels[i].transform.loc.set(p.x(), p.y(), p.z());
			wheels[i].transform.rot.set(q.x(), q.y(), q.z(), q.w());
			wheels[i].transform.dirty = true;
		}
		var trans = carChassis.getWorldTransform();
		var p = trans.getOrigin();
		var q = trans.getRotation();
		transform.loc.set(p.x(), p.y(), p.z());
		transform.rot.set(q.x(), q.y(), q.z(), q.w());
		var up = transform.world.up();
		transform.loc.add(up);
		transform.dirty = true;

		// TODO: fix parent matrix update
		if (camera.parent != null)
			camera.parent.transform.buildMatrix();
		camera.buildMatrix();
	}

	function createRigidBody(mass:Float, shape:BtCompoundShapePointer):BtRigidBodyPointer {
		var localInertia = BtVector3.create(0, 0, 0);
		shape.calculateLocalInertia(mass, localInertia);

		var centerOfMassOffset = BtTransform.create();
		centerOfMassOffset.setIdentity();

		var startTransform = BtTransform.create();
		startTransform.setIdentity();
		startTransform.setOrigin(BtVector3.create(transform.loc.x, transform.loc.y, transform.loc.z));
		startTransform.setRotation(BtQuaternion.create(transform.rot.x, transform.rot.y, transform.rot.z, transform.rot.w));

		var myMotionState = BtDefaultMotionState.create(startTransform, centerOfMassOffset);
		var cInfo = BtRigidBodyConstructionInfo.create(mass, myMotionState, shape, localInertia);

		var body = BtRigidBody.create(cInfo);
		
		body.setLinearVelocity(BtVector3.create(0, 0, 0));
		body.setAngularVelocity(BtVector3.create(0, 0, 0));

		//physics.world.addRigidBody(body);

		var rigidBody = new armory.trait.physics.bullet.RigidBody(1.0, 8, 0.5, 0.0, 0.0,
						0.04, 0.1, false,
						null, null,1, false, null, false, true, body);
		rigidBody.object = this.object;
		rigidBody.init();
		
		return rigidBody.body;
	}

	#if arm_azerty
	static inline var keyUp = 'z';
	static inline var keyDown = 's';
	static inline var keyLeft = 'q';
	static inline var keyRight = 'd';
	static inline var keyStrafeUp = 'e';
	static inline var keyStrafeDown = 'a';
	#else
	static inline var keyUp = 'w';
	static inline var keyDown = 's';
	static inline var keyLeft = 'a';
	static inline var keyRight = 'd';
	static inline var keyStrafeUp = 'e';
	static inline var keyStrafeDown = 'q';
	#end
	#end
}

class VehicleWheel {
	#if (!arm_bullet)
	public function new() {}
	#else
	public var isFrontWheel:Bool;
	public var wheelRadius:Float;
	public var wheelWidth:Float;

	var locX:Float;
	var locY:Float;
	var locZ:Float;

	public function new(id:Int, transform:Transform, vehicleTransform:Transform) {
		wheelRadius = transform.dim.z / 2;
		wheelWidth = transform.dim.x > transform.dim.y ? transform.dim.y : transform.dim.x;

		locX = transform.loc.x;
		locY = transform.loc.y;
		locZ = vehicleTransform.dim.z / 2 + transform.loc.z;
	}

	public function getConnectionPoint():BtVector3 {
		return BtVector3.create(locX, locY, locZ);
	}
	#end
}
