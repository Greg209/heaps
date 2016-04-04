package hxd.inspect;
import hxd.inspect.Property;

private class SceneObject extends TreeNode {

	public var o : h3d.scene.Object;
	public var visible = true;
	public var culled = false;

	public function new(o, p) {
		this.o = o;
		super(o.name != null ? o.name : o.toString(), p);
	}

	function objectName( o : h3d.scene.Object ) {
		var name = o.name != null ? o.name : o.toString();
		return name.split(".").join("_");
	}

	override function getPathName() {
		var name = objectName(o);
		if( o.parent == null )
			return name;
		var idx = Lambda.indexOf(@:privateAccess o.parent.childs, o);
		var count = 0;
		for( i in 0...idx )
			if( objectName(o.parent.getChildAt(i)) == name )
				count++;
		if( count > 0 )
			name += "@" + count;
		return name;
	}
}

private class CustomSceneProps extends SceneProps {

	var panel : ScenePanel;

	public function new(panel, scene) {
		this.panel = panel;
		super(scene);
	}

	override function addNode(name:String, icon:String, props:Void-> Array<Property>, ?parent:Node) : Node {
		return panel.addNode(name, icon, props, cast parent);
	}

	override function getMaterialShaderProps(mat:h3d.mat.Material, pass:h3d.mat.Pass, shader:hxsl.Shader) {
		var shaders = [for( s in pass.getShaders() ) s];
		shaders.reverse();
		var index = shaders.indexOf(shader);
		var p = super.getMaterialShaderProps(mat, pass, shader);
		p = PPopup(p, ["Toggle", "View Source"], function(j, i) {
			switch( i ) {
			case 0:
				if( index == 0 ) return; // Don't allow toggle base shader
				if( !pass.removeShader(shader) )
					pass.addShaderAt(shader, shaders.length - (index + 1));
				j.toggleClass("disable");
			case 1:
				var shader = @:privateAccess shader.shader;
				var p = new Panel(null, shader.data.name+" shader");
				var toString = hxsl.Printer.shaderToString;
				var code = toString(shader.data);
				p.j.html("<pre class='code'>" + colorize(code) + "</pre>");
				p.show();
			}
		});
		return p;
	}

	override function getMaterialPassProps(mat:h3d.mat.Material, pass:h3d.mat.Pass) {
		var p = super.getMaterialPassProps(mat, pass);
		p = PPopup(p, ["Toggle", "View Shader"], function(j, i) {
			switch( i ) {
			case 0:
				if( !mat.removePass(pass) )
					mat.addPass(pass);
				j.toggleClass("disable");
			case 1:
				var p = new Panel(null,pass.name+" shader");
				var shader = scene.renderer.compileShader(pass);
				var toString = hxsl.Printer.shaderToString;
				var code = toString(shader.vertex.data) + "\n\n" + toString(shader.fragment.data);
				p.j.html("<pre class='code'>" + colorize(code) + "</pre>");
				p.show();
			}
		});
		return p;
	}

	function colorize( code : String ) {
		code = code.split("\t").join("    ");
		code = StringTools.htmlEscape(code);
		code = ~/\b((var)|(function)|(if)|(else)|(for)|(while))\b/g.replace(code, "<span class='kwd'>$1</span>");
		code = ~/(@[A-Za-z]+)/g.replace(code, "<span class='meta'>$1</span>");
		return code;
	}

}

class ScenePanel extends Panel {

	var scene : h3d.scene.Scene;
	var sceneObjects : Array<SceneObject>;
	var scenePosition = 0;
	var currentPick(default,set) : h3d.scene.Mesh;
	var currentPickShader : hxsl.Shader;
	var btPick : cdb.jq.JQuery;
	var lastPickEvent : Null<Int>;
	var sprops : SceneProps;

	public function new(name, scene) {
		super(name, "Scene 3D");
		sceneObjects = [];
		this.scene = scene;
		sprops = new CustomSceneProps(this, scene);
	}

	override function initContent() {
		super.initContent();
		j.addClass("scene");
		j.html('
			<ul class="buttons">
				<li class="bt_hide" title="Show/Hide invisible objects">
					<i class="fa fa-eye" />
				</li>
				<li class="bt_pick" title="Pick object in game">
					<i class="fa fa-hand-o-up" />
				</li>
			</ul>
			<div class="scrollable">
				<ul class="elt root">
				</ul>
			</div>
		');
		content = j.find(".root");

		var bt = j.find(".bt_hide");
		bt.addClass("active");
		bt.click(function(_) {
			bt.toggleClass("active");
			content.toggleClass("masked");
		});

		btPick = j.find(".bt_pick");
		btPick.click(function(_) {
			btPick.toggleClass("active");
			var stage = hxd.Stage.getInstance();
			if( !btPick.hasClass("active") ) {
				currentPick = null;
				lastPickEvent = null;
				stage.removeEventTarget(onPickEvent);
				return;
			}
			lastPickEvent = 0;
			stage.addEventTarget(onPickEvent);
		});
	}

	function set_currentPick(m) {
		if( currentPick == m )
			return m;
		if( currentPick != null ) {
			currentPick.material.mainPass.removeShader(currentPickShader);
			currentPickShader = null;
		}
		currentPick = m;
		if( currentPick != null ) {
			var m = new h3d.shader.ColorMatrix();
			m.matrix.identity();
			m.matrix.colorHue(0.1);
			m.matrix.colorBrightness(0.2);
			currentPickShader = m;
			currentPick.material.mainPass.addShader(m);
		}
		return m;
	}

	function onPickEvent( e : hxd.Event ) {
		switch( e.kind ) {
		case EMove:
			lastPickEvent = h3d.Engine.getCurrent().frameCount;
			var obj = scene.hardwarePick(e.relX, e.relY);
			currentPick = obj == null ? null : obj.toMesh();
		case EPush:
			if( currentPick == null ) return;
			var cur = currentPick;
			currentPick = null;
			btPick.click();
			for( o in sceneObjects )
				if( o.o == cur ) {
					o.click();
					o.j.scrollIntoView();
					break;
				}
		default:
		}
	}

	public function addNode( name : String, icon : String, ?getProps : Void -> Array<Property>, ?parent : TreeNode ) {
		var n = new TreeNode(name, parent == null ? this : parent);
		n.icon = icon;
		n.props = getProps;
		if( getProps != null )
			n.onSelect = function() inspect.editProps(n);
		return n;
	}

	function getObjectIcon( o : h3d.scene.Object) {
		if( Std.is(o, h3d.scene.Skin) )
			return "child";
		if( Std.is(o, h3d.parts.Particles) || Std.is(o,h3d.parts.GpuParticles) )
			return "sun-o";
		if( Std.is(o, h3d.scene.Mesh) )
			return "cube";
		if( Std.is(o, h3d.scene.CustomObject) )
			return "globe";
		if( Std.is(o, h3d.scene.Scene) )
			return "picture-o";
		if( Std.is(o, h3d.scene.Light) )
			return "lightbulb-o";
		return null;
	}

	override function sync() {
		scenePosition = 0;
		syncRec(scene, this);
		while( sceneObjects.length > scenePosition )
			sceneObjects.pop().dispose();
		var frame = h3d.Engine.getCurrent().frameCount;
		if( lastPickEvent != null && lastPickEvent < frame - 1 ) {
			var stage = hxd.Stage.getInstance();
			var e = new hxd.Event(EMove, stage.mouseX, stage.mouseY);
			haxe.Timer.delay(function() { if( lastPickEvent == null ) return; onPickEvent(e); }, 0); // flash don't like to capture while rendering
		}
	}

	@:access(hxd.inspect.TreeNode)
	function syncRec( o : h3d.scene.Object, p : Node ) {
		var so = sceneObjects[scenePosition];
		if( so != null && so.o != o ) {
			for( i in scenePosition + 1...sceneObjects.length )
				if( sceneObjects[i].o == o ) {
					var tmp = sceneObjects[i];
					sceneObjects[i] = so;
					sceneObjects[scenePosition] = tmp;
					so = tmp;
					break;
				}
		}
		if( so == null || so.o != o ) {
			so = new SceneObject(o, p);
			sceneObjects.insert(scenePosition, so);
			var icon = getObjectIcon(o);
			so.icon = icon == null ? "circle-o" : getObjectIcon(o);
			so.props = function() return sprops.getObjectProps(o);
			so.onSelect = function() inspect.editProps(so);
		}

		if( so.parent != p ) so.parent = p;

		if( o.visible != so.visible ) {
			so.visible = o.visible;
			so.j.toggleClass("hidden");
		}
		@:privateAccess if( o.culled != so.culled ) {
			so.culled = o.culled;
			so.j.toggleClass("culled");
		}

		scenePosition++;
		if( o.numChildren > 0 ) {
			if( so.openIcon == null && so.icon == "circle-o" ) {
				so.openIcon = "circle-o";
				so.icon = "dot-circle-o";
			}
			for( c in o )
				syncRec(c, so);
		} else if( so.jchild != null ) {
			for( o in so.childs.copy() )
				o.dispose();
			if( so.openIcon == "circle-o" ) {
				so.openIcon = null;
				so.icon = "circle-o";
			}
		}
	}

}