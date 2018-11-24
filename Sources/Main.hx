// Auto-generated
package ;
class Main {
    public static inline var projectName = 'vehicle';
    public static inline var projectPackage = 'arm';
    public static inline var voxelgiVoxelSize = 64.0 / 128;
    public static inline var voxelgiHalfExtents = 32;
    public static function main() {
        iron.object.BoneAnimation.skinMaxBones = 8;
        iron.object.LightObject.cascadeCount = 4;
        iron.object.LightObject.cascadeSplitFactor = 0.800000011920929;
        armory.system.Starter.main(
            'Scene',
            0,
            true,
            true,
            false,
            1280,
            720,
            1,
            true,
            armory.renderpath.RenderPathCreator.get
        );
    }
}
