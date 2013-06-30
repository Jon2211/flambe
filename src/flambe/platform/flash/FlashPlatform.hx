//
// Flambe - Rapid game development
// https://github.com/aduros/flambe/blob/master/LICENSE.txt

package flambe.platform.flash;

#if flash11_2 import flash.events.ThrottleEvent; #end
import flash.Lib;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.events.TouchEvent;
import flash.events.UncaughtErrorEvent;
import flash.external.ExternalInterface;
import flash.media.SoundMixer;
import flash.media.SoundTransform;
import flash.net.SharedObject;
import flash.system.Capabilities;

import flambe.asset.AssetPack;
import flambe.asset.Manifest;
import flambe.subsystem.*;
import flambe.util.Logger;
import flambe.util.Promise;

class FlashPlatform
    implements Platform
{
    public static var instance (default, null) :FlashPlatform = new FlashPlatform();

    public var mainLoop (default, null) :MainLoop;

    private function new ()
    {
    }

    public function init ()
    {
        var stage = Lib.current.stage;

        _stage = new FlashStage(stage);
        _pointer = new BasicPointer();
        _mouse = FlashMouse.shouldUse() ? new FlashMouse(_pointer, stage) : new DummyMouse();
#if flambe_air
        _touch = AirTouch.shouldUse() ? new AirTouch(_pointer, stage) : new DummyTouch();
#else
        _touch = new DummyTouch();
#end

        _renderer = new Stage3DRenderer();
        mainLoop = new MainLoop();

        stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
        stage.addEventListener(Event.RENDER, onRender);

        Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(
            UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);

#if flash11_2
        // TODO(bruno): ThrottleEvent may not be exactly right, but VisibilityEvent is broken and
        // Event.ACTIVATE only handles focus
        // TODO(bruno): Get the currently throttled state when the app starts?
        stage.addEventListener(ThrottleEvent.THROTTLE, onThrottle);
        System.hidden.changed.connect(function (hidden,_) {
            if (!hidden) {
                _skipFrame = true;
            }
        });
#end

// #if flambe_air
//         // Ensure sound stops when the app is backgrounded or hardware muted on iOS
//         SoundMixer.audioPlaybackMode = "ambient";
// #end

#if !flambe_air
        // Hack to fix SharedObject in Chrome Flash:
        // https://groups.google.com/forum/#!topic/flambe/aD6KUvORWks
        getStorage();
#end

        System.volume.watch(function (volume, _) {
            var s = SoundMixer.soundTransform;
            s.volume = volume;
            SoundMixer.soundTransform = s;
        });

        _lastUpdate = Lib.getTimer();
        _skipFrame = false;
        _timeOffset = Date.now().getTime() - Lib.getTimer();

#if debug
        new DebugLogic(this);
#end
        Log.info("Initialized Flash platform", ["renderer", _renderer.getName()]);
    }

    public function loadAssetPack (manifest :Manifest) :Promise<AssetPack>
    {
        return new FlashAssetPackLoader(this, manifest).promise;
    }

    public function getStage () :StageSystem
    {
        return _stage;
    }

    public function getStorage () :StorageSystem
    {
        if (_storage == null) {
            try {
                _storage = new FlashStorage(SharedObject.getLocal("flambe"));
            } catch (err :Dynamic) {
                // SharedObject.getLocal may throw an error
                Log.warn("SharedObject is unavailable, falling back to unpersisted storage");
                _storage = new DummyStorage();
            }
        }
        return _storage;
    }

    public function getPointer () :PointerSystem
    {
        return _pointer;
    }

    public function getMouse () :MouseSystem
    {
        return _mouse;
    }

    public function getTouch () :TouchSystem
    {
        return _touch;
    }

    public function getKeyboard () :KeyboardSystem
    {
        if (_keyboard == null) {
            _keyboard = FlashKeyboard.shouldUse() ?
                new FlashKeyboard(_stage.nativeStage) : new DummyKeyboard();
        }
        return _keyboard;
    }

    public function getWeb () :WebSystem
    {
        if (_web == null) {
#if flambe_air
            if (AirWeb.shouldUse()) {
                _web = new AirWeb(_stage.nativeStage);
            } else {
                Log.warn("StageWebView is unavailable");
                _web = new FlashWeb();
            }
#else
            _web = new FlashWeb();
#end
        }
        return _web;
    }

    public function getExternal () :ExternalSystem
    {
        if (_external == null) {
            _external = FlashExternal.shouldUse() ? new FlashExternal() : new DummyExternal();
        }
        return _external;
    }

    public function getMotion () :MotionSystem
    {
        if (_motion == null) {
#if flambe_air
            if (AirMotion.shouldUse()) {
                _motion = new AirMotion();
            } else {
                Log.warn("Accelerometer is unavailable");
                _motion = new DummyMotion();
            }
#else
            _motion = new DummyMotion();
#end
        }
        return _motion;
    }

    public function getRenderer () :Renderer
    {
        return _renderer;
    }

    public function getLocale () :String
    {
        return Capabilities.language;
    }

    public function createLogHandler (tag :String) :LogHandler
    {
#if (debug || flambe_keep_logs)
        return new FlashLogHandler(tag);
#else
        return null;
#end
    }

    public function getTime () :Float
    {
        return (_timeOffset+Lib.getTimer()) / 1000;
    }

    private function onEnterFrame (_)
    {
        var now = Lib.getTimer();
        var dt = (now-_lastUpdate) / 1000;
        _lastUpdate = now;

        if (System.hidden._) {
            return; // Prevent updates while hidden
        }
        if (_skipFrame) {
            _skipFrame = false;
            return;
        }

        mainLoop.update(dt);
        Lib.current.stage.invalidate();
    }

    private function onRender (_)
    {
        mainLoop.render(_renderer);
    }

    private function onUncaughtError (event :UncaughtErrorEvent)
    {
        System.uncaughtError.emit(FlashUtil.getErrorMessage(event.error));
    }

#if flash11_2
    private function onThrottle (event :ThrottleEvent)
    {
        System.hidden._ = (event.state != "resume");
    }
#end

    // Statically initialized subsystems
    private var _mouse :MouseSystem;
    private var _pointer :BasicPointer;
    private var _renderer :Renderer;
    private var _stage :FlashStage;
    private var _touch :TouchSystem;

    // Lazily initialized subsystems
    private var _external :ExternalSystem;
    private var _keyboard :KeyboardSystem;
    private var _motion :MotionSystem;
    private var _storage :StorageSystem;
    private var _web :WebSystem;

    private var _lastUpdate :Int;
    private var _skipFrame :Bool;
    private var _timeOffset :Float;
}
