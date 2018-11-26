package arm;

import iron.object.ParticleSystem;
import armory.trait.physics.PhysicsWorld;

class WheelController extends iron.Trait {

    private var psys:ParticleSystem;
    public var isBrakeEffect:Bool;

	public function new() {
		super();

		notifyOnInit(function() {
            isBrakeEffect=false;
            var mo = cast(object, iron.object.MeshObject);
            psys = mo.particleSystems.length > 0 ? mo.particleSystems[0] : null;
		    if (psys == null) mo.particleOwner.particleSystems[0];
		});

		 notifyOnUpdate(updateWheelEffect);

		// notifyOnRemove(function() {
		// });
	}

	public function updateWheelEffect()	{
			    
            var enableEffect = true;

            if(isBrakeEffect != true)
            {
                var physics = PhysicsWorld.active;

                // Start from cone location
                var from = object.transform.world.getLoc();

                // Cast ray in the direction cone points to
                var to = object.transform.look();

                // 1000 units long
                to.mult(10);

                // End position
                to.add(from);
                
                var rb = physics.rayCast(from, to);
                if (rb != null) {
                    if (rb.object.name == "ground.physics") {
                        enableEffect = true;
                    }
                }
            }

        // If it it is break, or on dirt, enable it, otherwise disable effect
       // if((enableEffect == true) || (isBrakeEffect == true))
       if (isBrakeEffect == true)
        {
            psys.enableLifetime();
        }
        else 
        {
            psys.disableLifetime();
        }
	}
}
