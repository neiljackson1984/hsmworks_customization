/**
  Mach3Mill post processor configuration. for HSMWorks.
  
  

*/

description = "Autoscan Gantry Mill";
vendor = "Autoscan";
vendorUrl = "http://autoscaninc.com";
legal = "";
description="This is the post-processor description. Lorem Ipsum dolorem sit amet. ";
certificationLevel = 2;
//minimumRevision = 24000;

extension = "nc";
setCodePage("ascii");

var debugging = false;

/*
Boolean mapWorkOrigin 
Specifies that the section origin should be mapped to (0, 0, 0). When disabled the post is responsible for handling the section origin. By default this is enabled. 
*/
mapWorkOrigin =true;

/*
Boolean mapToWCS 
Specifies that the section work plane should be mapped to the WCS. When disabled the post is responsible for handling the WCS and section work plane. By default this is enabled. 
*/
mapToWCS = true;

//debugMode=true;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = 0;  //undefined; // set to 0 to forbid any circular motion and to undefined to allow circular motion on any plane



// user-defined properties
properties = {
  writeMachine: true, // write machine
  writeTools: true, // writes the tools
  useG28: false, // disable to avoid G28 output for safe machine retracts - when disabled you must manually ensure safe retracts
  useM6: false, // disable to avoid M6 output - preload is also disabled when M6 is disabled
  useG43WithM6ForToolchanges: true, //if useM6 is true, then whenever we output an M6, we will immediately afterward output a G43 to enable the tool length offset for the newly selected tool.
  preloadTool: false, // preloads next tool on tool change if any
  showSequenceNumbers: false, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 5, // increment for sequence numbers
  optionalStop: true, // optional stop
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
  useRadius: true, // specifies that arcs should be output using the radius (R word) instead of the I, J, and K words.
  dwellInSeconds: true, // specifies the unit for dwelling: true:seconds and false:milliseconds.
  solidworksEquationsJsonFile: "",
  useRetractionHackInSetWorkPlane: false
};

var solidworksGlobalVariables;


var permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,=_-";

var mapCoolantTable = new Table(
  [9, 8, 7],
  {initial:COOLANT_OFF, force:true},
  "Invalid coolant mode"
);

var nFormat = createFormat({prefix:"N", decimals:0});
var gFormat = createFormat({prefix:"G", decimals:1});
var mFormat = createFormat({prefix:"M", decimals:0});
var hFormat = createFormat({prefix:"H", decimals:0});
var pFormat = createFormat({prefix:"P", decimals:(unit == MM ? 3 : 4), scale:0.5});
var param1Format = createFormat({prefix:"P", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param1()
var param2Format = createFormat({prefix:"Q", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param2()
var param3Format = createFormat({prefix:"R", decimals:7});  //this format spec is used for the argument that mach3 scripts called from gcode will read as Param3()
var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var rFormat = xyzFormat; // radius
var abcFormat = createFormat({decimals:3, forceDecimal:true, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1), forceDecimal:true});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-99999.999
var milliFormat = createFormat({decimals:0}); // milliseconds // range 1-9999
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({prefix:"Z"}, xyzFormat);
var aOutput = createVariable({prefix:"A"}, abcFormat);
var bOutput = createVariable({prefix:"B"}, abcFormat);
var cOutput = createVariable({prefix:"C"}, abcFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);
var pOutput = createVariable({}, pFormat);

// circular output
var iOutput = createReferenceVariable({prefix:"I", force:true}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J", force:true}, xyzFormat);
var kOutput = createReferenceVariable({prefix:"K", force:true}, xyzFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // G93-94
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21
var gCycleModal = createModal({}, gFormat); // modal group 9 // G81, ...
var gRetractModal = createModal({}, gFormat); // modal group 10 // G98-99

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;


function movementToString(movement)
{
	switch (movement) {
		case MOVEMENT_RAPID : return "MOVEMENT_RAPID" ; break;
		case MOVEMENT_LEAD_IN  : return "MOVEMENT_LEAD_IN" ; break;
		case MOVEMENT_CUTTING  : return "MOVEMENT_CUTTING" ; break;
		case MOVEMENT_LEAD_OUT  : return "MOVEMENT_LEAD_OUT" ; break;
		case MOVEMENT_LINK_TRANSITION  : return "MOVEMENT_LINK_TRANSITION" ; break;
		case MOVEMENT_LINK_DIRECT  : return "MOVEMENT_LINK_DIRECT" ; break;
		case MOVEMENT_RAMP_HELIX  : return "MOVEMENT_RAMP_HELIX" ; break;
		case MOVEMENT_RAMP_PROFILE  : return "MOVEMENT_RAMP_PROFILE" ; break;
		case MOVEMENT_RAMP_ZIG_ZAG  : return "MOVEMENT_RAMP_ZIG_ZAG" ; break;
		case MOVEMENT_RAMP  : return "MOVEMENT_RAMP" ; break;
		case MOVEMENT_PLUNGE  : return "MOVEMENT_PLUNGE" ; break;
		case MOVEMENT_PREDRILL  : return "MOVEMENT_PREDRILL" ; break;
		case MOVEMENT_EXTENDED  : return "MOVEMENT_EXTENDED" ; break;
		case MOVEMENT_REDUCED  : return "MOVEMENT_REDUCED" ; break;
		case MOVEMENT_FINISH_CUTTING  : return "MOVEMENT_FINISH_CUTTING" ; break;
		case MOVEMENT_HIGH_FEED  : return "MOVEMENT_HIGH_FEED" ; break;
		default: return "unknown movement";
	}
	return "unknown movement";
}

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2(nFormat.format(sequenceNumber % 100000), arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("(" + filterText(String(text).toUpperCase(), permittedCommentChars) + ")");
}



function getMethods(obj)
{
    var res = [];
    for(var m in obj) {
        if(typeof obj[m] == "function") {
            res.push(m)
        }
    }
    return res;
}


function reconstruct(obj)
{
    var names = Object.getOwnPropertyNames(obj);
	var res = {};
    for each (var name in names) {		
		if(typeof obj[name] == "function") {
            res[name] = obj[name].toSource();
        } else {
		    res[name] = JSON.stringify(obj[name]);
		}
		
    }
    return res;
}

function dump(obj,name)
{
	writeln("");
	writeln("JSON.stringify(getMethods("+name+"),null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(getMethods(obj),null,'\t'));
	
	writeln("");
	writeln("JSON.stringify("+name+".keys,null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(obj.keys,null,'\t'));
	
	writeln("");
	writeln("JSON.stringify(reconstruct("+name+"),null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(reconstruct(obj),null,'\t'));
	
	writeln("");
	writeln("JSON.stringify(Object.getOwnPropertyNames("+name+"),null,'\t')   >>>>>>>>>>>>>>");
	writeln(JSON.stringify(Object.getOwnPropertyNames(obj),null,'\t'));
	
	
	
}

function onOpen() {
	
	//read solidworks global variables from the specified file.
	if ( (typeof properties.solidworksEquationsJsonFile === 'string') && (properties.solidworksEquationsJsonFile.length > 0))
	{
		solidworksGlobalVariables = getObjectFromJsonFile(properties.solidworksEquationsJsonFile);
	}
	
	// writeln("JSON.stringify(properties,null,'\\t')   >>>>>>>>>>>>>>");
	// writeln(JSON.stringify(properties,null,'\t'));





	// writeln("JSON.stringify(solidworksGlobalVariables,null,'\\t')   >>>>>>>>>>>>>>");
	// writeln(JSON.stringify(solidworksGlobalVariables,null,'\t'));
	
	//var myPostPocessor = new PostProcessor();
//dump(myPostPocessor,"myPostPocessor");
	// // writeln("");
	// // writeln("JSON.stringify(this,null,'\t')   >>>>>>>>>>>>>>");
	// // writeln(JSON.stringify(this,null,'\t'));
	
	// // writeln("");
	// // writeln("JSON.stringify(this.prototype,null,'\t')   >>>>>>>>>>>>>>");
	// // writeln(JSON.stringify(this.prototype,null,'\t'));
	
	// // writeln("");
	// // writeln("JSON.stringify(getMethods(this),null,'\t')   >>>>>>>>>>>>>>");
	// // writeln(JSON.stringify(getMethods(this),null,'\t'));
	
	// // writeln("");
	// // writeln("JSON.stringify(this.keys,null,'\t')   >>>>>>>>>>>>>>");
	// // writeln(JSON.stringify(this.keys,null,'\t'));
	
	// writeln("");
	// writeln("JSON.stringify(reconstruct(this),null,'\t')   >>>>>>>>>>>>>>");
	// writeln(JSON.stringify(reconstruct(this),null,'\t'));
	

	
	//writeln(">>>>>>>>>>>>>>>>>  machineConfiguration.getModel() is " + machineConfiguration.getModel());
	//writeln(">>>>>>>>>>>>>>>>>  machineConfiguration.getDescription() is " + machineConfiguration.getDescription());
   
	//optimizeMachineAngles2(0); // TCP (i.e. Tool Center Point) mode  //in this mode, the coordinates that appear as numbers in the gcode are the coordinates of the tip of the tool in the work frame.  This is not what we want.
	//writeln("got this far");
  
  
   //optimizeMachineAngles2(1); // map tip mode  //in this mode, the coordinates that appear as numbers in the gcode are the coordinates of the tip in the machine frame.  This is what we want.	
  //optimizeMachineAngles2(0); // TCP (i.e. Tool Center Point) mode  //in this mode, the coordinates that appear as numbers in the gcode are the coordinates of the tip of the tool in the work frame.  This is not what we want.
  optimizeMachineAngles2(1); // map tip mode  //in this mode, the coordinates that appear as numbers in the gcode are the coordinates of the tip in the machine frame.  This is what we want.	
  
  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
	writeComment("A output is disabled");
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
		writeComment("B output is disabled");
  }
  if (!machineConfiguration.isMachineCoordinate(2)) {
    cOutput.disable();
		writeComment("C output is disabled");
  }
  
  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // dump tool information
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }
  
  if (false) {
    // check for duplicate tool number
    for (var i = 0; i < getNumberOfSections(); ++i) {
      var sectioni = getSection(i);
      var tooli = sectioni.getTool();
      for (var j = i + 1; j < getNumberOfSections(); ++j) {
        var sectionj = getSection(j);
        var toolj = sectionj.getTool();
        if (tooli.number == toolj.number) {
          if (xyzFormat.areDifferent(tooli.diameter, toolj.diameter) ||
              xyzFormat.areDifferent(tooli.cornerRadius, toolj.cornerRadius) ||
              abcFormat.areDifferent(tooli.taperAngle, toolj.taperAngle) ||
              (tooli.numberOfFlutes != toolj.numberOfFlutes)) {
            error(
              subst(
                localize("Using the same tool number for different cutter geometry for operation '%1' and '%2'."),
                sectioni.hasParameter("operation-comment") ? sectioni.getParameter("operation-comment") : ("#" + (i + 1)),
                sectionj.hasParameter("operation-comment") ? sectionj.getParameter("operation-comment") : ("#" + (j + 1))
              )
            );
            return;
          }
        }
      }
    }
  }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90), gFeedModeModal.format(94), gFormat.format(91.1), gFormat.format(40), gFormat.format(49), gPlaneModal.format(17));

  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(20));
    break;
  case MM:
    writeBlock(gUnitModal.format(21));
    break;
  }
}

function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
  aOutput.reset();
  bOutput.reset();
  cOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  forceABC();
  feedOutput.reset();
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}


function setWorkPlane(abc) {
	if(debugging){writeln("setWorkPlane("+abc+") was called.");}
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  // if currentWorkPlaneABC is defined AND the argument, abc, is the same as currentWorkPlaneABC, then we do not need to do anything, so return; else proceed.
  if (!(
		(currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z)
	)) {
    return; // no change
  }

  onCommand(COMMAND_UNLOCK_MULTI_AXIS); //in the post processor as it is now (2015/11/05), the COMMAND_UNLOCK_MULTI_AXIS and COMMAND_LOCK_MULTI_AXIS do not do anything.  I guess the idea is that, for some machines, the command would correspond to an Mcode that needed to be added to the output file, in which case onCommand(...) would take care of this.

  // NOTE: add retract here
	if(properties.useRetractionHackInSetWorkPlane)
	{
	  // BEGIN HACK TO IMPLEMENT RETRACTION
	  //CAUTION: THIS IS A TOTAL HACK (I will eventaully wrap my head around the layers of generalizing that occur to go
	  //  from the tool moving (and orienting) around in modelspace to 
	  //the numbers that appear in gcode.) For now, I am inserting some hardcoded g-code 
	  //here that should (god willing) work for my purposes with the autoscan gantry mill.
	  //These hardcoded numbers could easily become a major problem if any of a number of changes are made (like changing to metric units in the gcode, for instance), so be careful,
	  //The goal is that, when we need to rotate the rotary axis to a new rotary index position (in preparation for a 2d or 3d operation at a different rotation from last operation),
	  //we want to make sure that the tool does not collide with the work during the rotation.
	   writeln("(BEGIN RETRACTION HACK WITHIN setWorkPlane)");
	   
	   writeBlock(
		gMotionModal.format(0),
		zOutput.format(2)
		);
		
		// writeBlock(
		// gMotionModal.format(0),
		// xOutput.format(-4)
		// );
	  writeln("(END RETRACTION HACK WITHIN setWorkPlane)");
	  //END HACK TO IMPLEMENT RETRACTION
	}
  writeBlock(
    gMotionModal.format(0),
    conditional(machineConfiguration.isMachineCoordinate(0), "A" + abcFormat.format(abc.x)),
    conditional(machineConfiguration.isMachineCoordinate(1), "B" + abcFormat.format(abc.y)),
    conditional(machineConfiguration.isMachineCoordinate(2), "C" + abcFormat.format(abc.z))
  );
  
  onCommand(COMMAND_LOCK_MULTI_AXIS);

  currentWorkPlaneABC = abc;
}

var closestABC = false; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }
  
  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }
  
  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }
  
  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }

  //var tcp = true;
  var tcp = false; //trying this per forum post. -Neil
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }
  
  return abc;
}

function onSection() {

if(debugging) {
	writeln("currentSection.workPlane: " + currentSection.workPlane);
	writeln("currentSection.getWorkPlane(): " + currentSection.getWorkPlane());
	dump(new Record(),"Record()");
	dump({a:25,b:35},"{a:25,b:35}");
	dump(this,"this");
}

  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());
  if (insertToolCall || newWorkOffset || newWorkPlane) {
    
    if (properties.useG28) {
      // retract to safe plane
      retracted = true;
      writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
      writeBlock(gAbsIncModal.format(90));
      zOutput.reset();
    }
  }

  writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    forceWorkPlane();
    
    onCommand(COMMAND_STOP_SPINDLE);
    onCommand(COMMAND_COOLANT_OFF);
  
    if (!isFirstSection() && properties.optionalStop) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > 256) {
      warning(localize("Tool number exceeds maximum value."));
    }

    if (properties.useM6) {
      writeBlock("T" + toolFormat.format(tool.number), mFormat.format(6));
	  	//might consider emitting a "G43" here to turn on the tool offset.
		if(properties.useG43WithM6ForToolchanges)
		{
			writeBlock(gFormat.format(43) + " (enable tool length offset)");
		}
    } else {
      writeBlock("T" + toolFormat.format(tool.number));
    }

	
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }

    if (properties.preloadTool && properties.useM6) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        writeBlock("T" + toolFormat.format(nextTool.number));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstToolNumber = section.getTool().number;
        if (tool.number != firstToolNumber) {
          writeBlock("T" + toolFormat.format(firstToolNumber));
        }
      }
    }
  }
  
  // if (insertToolCall ||
      // isFirstSection() ||
      // (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) ||
      // (tool.clockwise != getPreviousSection().getTool().clockwise)) 
	
	if(true) { //I always (not just when it is strictly necessary) want to write a spindle speed and spindle start command, just in case these values have been unwittingly mucked with by the user before getting to this point in the program.
    if (tool.spindleRPM < 1) {
      error(localize("Spindle speed out of range."));
      return;
    }
    if (tool.spindleRPM > 99999) {
      warning(localize("Spindle speed exceeds maximum value."));
    }
    writeBlock(
      sOutput.format(tool.spindleRPM), mFormat.format(tool.clockwise ? 3 : 4)
    );
  }

  // wcs
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      var p = workOffset; // 1->... // G59 P1 is the same as G54 and so on
      if (p > 254) {
        error(localize("Work offset out of range."));
      } else {
        if (workOffset != currentWorkOffset) {
          writeBlock(gFormat.format(59), "P" + p); // G59 P
          currentWorkOffset = workOffset;
        }
      }
    } else {
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
		writeBlock("M201");  //added to support mach3 formula axis correction on Autoscan Gantry Mill
		writeBlock("G0 A0");  //if we call "M201", we need to call "G0 A0" immediately afterwards to prevent the transforming preprocessor from inserting rotary wind-up.
      }
    }
  }

  forceXYZ();

  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    var abc = new Vector(0, 0, 0);
    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
    } else {
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
    }
    setWorkPlane(abc);
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  // set coolant after we have positioned at Z
  {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c));
    } else {
      warning(localize("Coolant not supported."));
    }
  }

  forceAny();
  gMotionModal.reset();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    //if (getCurrentPosition().z < initialPosition.z) {
	if (true) { //hack to retract. -Neil
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
	  if(debugging){writeln("RETRACTED");}
	  //// commented this out because it was moving z downwards when rotary axis was set at 180 degrees.
    }
  }

  if (insertToolCall || retracted) {
    var lengthOffset = tool.lengthOffset;
    if (lengthOffset > 256) {
      error(localize("Length offset out of range."));
      return;
    }

    gMotionModal.reset();
    writeBlock(gPlaneModal.format(17));
    
    if (!machineConfiguration.isHeadConfiguration()) {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
      );
      writeBlock(gMotionModal.format(0), gFormat.format(43), zOutput.format(initialPosition.z), hFormat.format(lengthOffset));
    } else {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0),
        gFormat.format(43), xOutput.format(initialPosition.x),
        yOutput.format(initialPosition.y),
        zOutput.format(initialPosition.z), hFormat.format(lengthOffset)
      );
    }
  } else {
    writeBlock(
      gAbsIncModal.format(90),
      gMotionModal.format(0),
      xOutput.format(initialPosition.x),  //THIS WILL HAVe TO BE FIXED TO WORK WITH THE NEW ANGLE-AWARE ONLINEAR FUNCTION. --NEED SINGLE UNIFIED MOTION FUNCTION.
      yOutput.format(initialPosition.y)
    );
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  if (properties.dwellInSeconds) {
    writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
  } else {
    milliseconds = clamp(1, seconds * 1000, 99999999);
    writeBlock(gFormat.format(4), "P" + milliFormat.format(milliseconds));
  }
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed));
}

function onCycle() {
  writeBlock(gPlaneModal.format(17));
}

function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + xyzFormat.format(r)];
}

function onCyclePoint(x, y, z) {
  if (isFirstCyclePoint()) {
    repositionToCycleClearance(cycle, x, y, z);
    
    // return to initial Z which is clearance plane and set absolute mode

    var F = cycle.feedrate;
    var P = (cycle.dwell == 0) ? 0 : cycle.dwell; // in seconds

    switch (cycleType) {
    case "drilling":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "counter-boring":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(82),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "chip-breaking":
      // cycle.accumulatedDepth is ignored
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(73),
          getCommonCycle(x, y, z, cycle.retract),
          "Q" + xyzFormat.format(cycle.incrementalDepth),
          feedOutput.format(F)
        );
      }
      break;
    case "deep-drilling":
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(83),
          getCommonCycle(x, y, z, cycle.retract),
          "Q" + xyzFormat.format(cycle.incrementalDepth),
          // conditional(P > 0, "P" + secFormat.format(P)),
          feedOutput.format(F)
        );
      }
      break;
    case "tapping":
      if (tool.type == TOOL_TAP_LEFT_HAND) {
        expandCyclePoint(x, y, z);
      } else {
        if (!F) {
          F = tool.getTappingFeedrate();
        }
        writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(84),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "left-tapping":
      expandCyclePoint(x, y, z);
      break;
    case "right-tapping":
      if (!F) {
        F = tool.getTappingFeedrate();
      }
      writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(84),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "fine-boring":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(76),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secFormat.format(P),
        "Q" + xyzFormat.format(cycle.shift),
        feedOutput.format(F)
      );
      break;
    case "back-boring":
      var dx = (gPlaneModal.getCurrent() == 19) ? cycle.backBoreDistance : 0;
      var dy = (gPlaneModal.getCurrent() == 18) ? cycle.backBoreDistance : 0;
      var dz = (gPlaneModal.getCurrent() == 17) ? cycle.backBoreDistance : 0;
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(87),
        getCommonCycle(x - dx, y - dy, z - dz, cycle.bottom),
        "I" + xyzFormat.format(cycle.shift),
        "J" + xyzFormat.format(0),
        "P" + secFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "reaming":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "stop-boring":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(86),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "manual-boring":
      writeBlock(
        gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(88),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "boring":
      if (P > 0) {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      writeBlock(xOutput.format(x), yOutput.format(y));
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    zOutput.reset();
  }
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

//diagnostic function to figure out what the hell HSMWorks is doing
function reportPosition()
{
  writeln("getRotation():" + getRotation());
  writeln("getTranslation():" + getTranslation());
  try {writeln("getPosition(): " + getPosition());} catch(e){} //{writeln("getPosition() failed");}
  try {writeln("getEnd(): " + getEnd());} catch(e){} //{writeln("getEnd() failed");}
  try {writeln("getDirection(): " + getDirection());} catch(e){} //{writeln("getDirection() failed");}
  writeln("getCurrentPosition(): " + getCurrentPosition());
  writeln("getCurrentGlobalPosition(): " + getCurrentGlobalPosition());
  writeln("getCurrentDirection(): " + getCurrentDirection());
  writeln("getPositionU(0): " + getPositionU(0));
  writeln("getPositionU(0.9999): " + getPositionU(0.9999));
  writeln("getPositionU(1): " + getPositionU(1));
  try {writeln("getDirectionU(1): " + getDirectionU(1));} catch(e){} //{writeln("getDirectionU(1) failed");}
  writeln("getCurrentNCLocation(): " + getCurrentNCLocation());
}


function onRapid(_x, _y, _z) {
	if(debugging){
	  writeln("");
	  writeln("onRapid("+_x+", "+_y+", "+_z+") was called)");
	  reportPosition();
	}
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y, z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
	if(debugging){
	  writeln("");
	  writeln("onLinear("+_x+", "+_y+", "+_z+", "+feed+") was called)");
	  reportPosition();
	}
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      writeBlock(gPlaneModal.format(17));
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        pOutput.reset();
        writeBlock(gMotionModal.format(1), pOutput.format(tool.diameter), gFormat.format(41), x, y, z, f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        pOutput.reset();
        writeBlock(gMotionModal.format(1), pOutput.format(tool.diameter), gFormat.format(42), x, y, z, f);
        break;
      default:
        writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
if(debugging){
  writeln("");
	writeln("onRapid5D("+_x+", "+_y+", "+_z+", "+_a+", "+_b+", "+_c+") was called)");
    reportPosition();
	}
	//commented out the following lines because they were preventing toolpath from being made
  // if (!currentSection.isOptimizedForMachine()) {
    // error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    // return;
  // } 
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  writeBlock(gMotionModal.format(0), x, y, z, a, b, c, "(" + movementToString(movement) + ")");
  feedOutput.reset();
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
if(debugging){
  writeln("");
writeln("onLinear5D("+_x+", "+_y+", "+_z+", "+_a+", "+_b+", "+_c+", "+feed+") was called)");
  reportPosition();
  }
	//commented out the following lines because they were preventing toolpath from being made
  // if (!currentSection.isOptimizedForMachine()) {
    // error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    // return;
  // }
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    return;
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  var f = feedOutput.format(feed);
  if (x || y || z || a || b || c) {
    writeBlock(gMotionModal.format(1), x, y, z, a, b, c, f, "(" + movementToString(movement) + ")");
	//writeComment("movement: " + movementToString(movement));
	//writeComment("length: " + Math.sqrt(Math.pow(_a,2) + Math.pow(_b,2) + Math.pow(_c,2)));
	//writeComment("test: " + Math.sqrt(Math.pow(3,2) + Math.pow(4,2)));
	//writeComment("_a,_b,_c: " + _a + ", " + _b + ", " + _c );
	//writeComment("Number/@_a,_b,_c: " + Number(_a) + ", " + Number(_b) + ", " + Number(_c) );
	//writeComment("typeof/@_a,_b,_c: " + typeof(_a) + ", " + typeof(_b) + ", " + typeof(_c) );
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f, "(" + movementToString(movement) + ")");
    }
  }
}

// function toMachineCoordinates(_x, _y, _z, _sx, _sy, _sz)
// {
	// var machineCoordinates = {};
	// var p = [_x,_y,_z];
	// var machZHat = [_sx,_sy,_sz];
	// var machYHat = [0,1,0];
	// var machXHat = // machYHat CROSS machZHat
	// [
		// machYHat[1]*machZHat[2] - machYHat[2]*machZHat[1],
		// machYHat[2]*machZHat[0] - machYHat[0]*machZHat[2],
		// machYHat[0]*machZHat[1] - machYHat[1]*machZHat[0],
	// ]

	// var pDotMachXHat = p[0]*machXHat[0] + p[1]*machXHat[1] + p[2]*machXHat[2]
	// var pDotMachYHat = p[0]*machYHat[0] + p[1]*machYHat[1] + p[2]*machYHat[2]
	// var pDotMachZHat = p[0]*machZHat[0] + p[1]*machZHat[1] + p[2]*machZHat[2]

	// var a = -Math.atan2(_sx,_sz);
	
	
	// machineCoordinates.x = pDotMachXHat;
	// machineCoordinates.y = pDotMachYHat;
	// machineCoordinates.z = pDotMachZHat;
	// machineCoordinates.a = a;
	// machineCoordinates.b = 0;
	// machineCoordinates.c = 0;
	
	// return machineCoordinates;
// }


// function onRapid5D(_x, _y, _z, _sx, _sy, _sz) {
	// //commented out the following lines because they were preventing toolpath from being made
  // // if (!currentSection.isOptimizedForMachine()) {
    // // error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    // // return;
  // // } 
  // if (pendingRadiusCompensation >= 0) {
    // error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    // return;
  // }
  // var machineCoordinates = toMachineCoordinates(_x, _y, _z, _sx, _sy, _sz);
  // var x = xOutput.format(machineCoordinates.x);
  // var y = yOutput.format(machineCoordinates.y);
  // var z = zOutput.format(machineCoordinates.z);
  // var a = aOutput.format(machineCoordinates.a);
  // var b = bOutput.format(machineCoordinates.b);
  // var c = cOutput.format(machineCoordinates.c);
  // writeBlock(gMotionModal.format(0), x, y, z, a, b, c);
  // feedOutput.reset();
// }

// function onLinear5D(_x, _y, _z, _sx, _sy, _sz, feed) {
	// //commented out the following lines because they were preventing toolpath from being made
  // // if (!currentSection.isOptimizedForMachine()) {
    // // error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    // // return;
  // // }
  // if (pendingRadiusCompensation >= 0) {
    // error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    // return;
  // }
  
  
  // var machineCoordinates = toMachineCoordinates(_x, _y, _z, _sx, _sy, _sz);
  
  // var x = xOutput.format(machineCoordinates.x);
  // var y = yOutput.format(machineCoordinates.y);
  // var z = zOutput.format(machineCoordinates.z);
  // var a = aOutput.format(machineCoordinates.a);
  // var b = bOutput.format(machineCoordinates.b);
  // var c = cOutput.format(machineCoordinates.c);
  // var f = feedOutput.format(feed);
  // if (x || y || z || a || b || c) {
    // writeBlock(gMotionModal.format(1), x, y, z, a, b, c, f, "(" + movementToString(movement) + ")");
	// //writeComment("movement: " + movementToString(movement));
  // } else if (f) {
    // if (getNextRecord().isMotion()) { // try not to output feed without motion
      // feedOutput.reset(); // force feed on next line
    // } else {
      // writeBlock(gMotionModal.format(1), f);
    // }
  // }
// }


function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
if(debugging){
	  writeln("");
	writeln("onCircular("+clockwise+", "+cx+", "+cy+", "+cz+", "+x+", "+y+", "+z+", "+feed+") was called)");
	  reportPosition();
	  }
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (properties.useRadius || isHelical()) { // radius mode does not support full arcs
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else if (!properties.useRadius) {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else { // use radius mode
    var r = getCircularRadius();
    if (toDeg(getCircularSweep()) > (180 + 1e-9)) {
      r = -r; // allow up to <360 deg arcs
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2,
  COMMAND_SPINDLE_CLOCKWISE:3,
  COMMAND_SPINDLE_COUNTERCLOCKWISE:4,
  COMMAND_STOP_SPINDLE:5,
  COMMAND_ORIENTATE_SPINDLE:19,
  COMMAND_LOAD_TOOL:6,
  COMMAND_COOLANT_ON:8, // flood
  COMMAND_COOLANT_OFF:9
};

function onCommand(command) {
  
  //writeln(">>>>>>>>>>>>>>>>>  onCommand( " + command +  " ) ");
  switch (command) {
  case COMMAND_START_SPINDLE:
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }
  
  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
  //writeln(">>>>>>>>>>>>>>>>>  endCommand ");
}

/*
Inserts an external file into the gcode output.  the path is relative to the output gcode file (or can also be absolute).
If the file estension is "php", this is a special case: in this case, the php file is executed and the stdout is included in 
the output gcode file.
*/
function includeFile(path)
{
	writeln("(>>>>>>>>>>>>>>>>>  file to be included: " + path + ")"); //temporary behavior for debugging.
	//if path is not absolute, it will be assumed to be relative to the folder where the output file is being placed.
	
	var absolutePath = 
		FileSystem.getCombinedPath(
			FileSystem.getFolderPath(getOutputPath()) ,
			path
		);
	
	var fileExtension = FileSystem.getFilename(path).replace(FileSystem.replaceExtension(FileSystem.getFilename(path)," ").slice(0,-1),""); //this is a bit of a hack to work around the fact that there is no getExtension() function.  Strangely, FileSystem.replaceExtension strips the period when, and only when, the new extension is the emppty string.  I ought to do all of this with RegEx.  //bizarrely, replaceExtension() evidently regards the extension of the file whose name is "foo" to be "foo" --STUPID (but this weirdness won't affect my current project.)
	
	// //writeln("getOutputPath():\""+getOutputPath()+"\"");
	// //writeln("FileSystem.getFilename(path):\"" + FileSystem.getFilename(path) + "\"");
	// writeln("fileExtension:\""+fileExtension+"\"");
	// writeln("absolutePath:\"" + absolutePath + "\"");
	// writeln("FileSystem.getTemporaryFolder():\"" + FileSystem.getTemporaryFolder() + "\"");
	var fileToBeIncludedVerbatim;
	var returnCode;
	switch(fileExtension.toLowerCase()){ //FIX
		case "php" :
			//FileSystem.getTemporaryFile() was not working, until I discovered that the stupid thing was trying to create a file in a non-existent temporary folder.
			// Therefore, I must first ensure that the temporary folder exists.  STUPID!
			if(! FileSystem.isFolder(FileSystem.getTemporaryFolder())){FileSystem.makeFolder(FileSystem.getTemporaryFolder());}
			var tempFile = FileSystem.getTemporaryFile("");
			//writeln("tempFile:\""+tempFile+"\"");
			returnCode = execute("cmd", "/c php \""+absolutePath+"\" > \""+tempFile+"\"", false, ""); //run it through php and collect the output
			//writeln("returnCode:"+returnCode);
			fileToBeIncludedVerbatim = tempFile;
			break;
		
		default :
			fileToBeIncludedVerbatim = absolutePath;
			break;
	
	}
	
	var myTextFile = new TextFile(fileToBeIncludedVerbatim,false,"ansi");
	var lineCounter = 0;
	var line;
	while(!function(){try {line=myTextFile.readln(); eof = false;} catch(error) {eof=true;} return eof;}())  //if the final line is empty (i.e. if the last character in the file is a newline, then that line is not read. So, for instance, an empty file is considered to have 0 lines, according to TextFile.readln. Weird.).
	{
		writeln(line);
		lineCounter++;
	}
	myTextFile.close();
	//writeln("read " + lineCounter + " lines.");
}

function steadyRest_engage(diameter, returnImmediately)
{
	if (typeof returnImmediately == 'undefined') {returnImmediately = false;}
	writeln("");
	writeln("");
	// ought to move to a convenient position here.
	// writeln("G0 Z1.7 (go to safe z)");
	// writeln("G0 X-8 Y53 (traverse laterally to a position where the spindle won't interfere with your hands reaching into the machine to engage the steady rest.)");
	// writeln("M5 (turn off spindle)");
	// writeln("M9 (turn off dust collector)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(MIKE, ENGAGE THE STEADY REST.  THEN PRESS 'RESUME')");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("M0"); 
	// writeln("M3 (turn on spindle)");
	// writeln("M8 (turn on dust collector)");	
	
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(NOW DRIVING THE STEADYREST TO DIAMETER: " + diameter +  "inches )");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");
	// writeln("(>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)");

	writeBlock(mFormat.format(203), param1Format.format(diameter), (returnImmediately ? param2Format.format(1) : ""), "( DRIVE STEADYREST TO DIAMETER=" + diameter + " " + (returnImmediately ? "and return immediately" : "and wait for steadyrest move to finish before proceeding") + ")");

}

function steadyRest_home()
{
	writeln("");
	writeln("");

	writeBlock(mFormat.format(204), "( HOME THE STEADYREST )");

}

function onAction(value)  //this onAction() function is not a standard member function of postProcessor, but my own invention.
{
	//writeln("onAction ran with value:" + value);

	
	// // // var tokens;
	// // // tokens = tokenize(value); //FIX ME
	
	// // // switch(tokens[0]){
		// // // case "include" :
			// // // includeFile(tokens[1]);
			// // // break;
		
		// // // default :
			// // // //possibly issue an error message here.
			// // // break;
	// // // }
	// // // if (tokens[0]=="include")
	// // // {
	
	// // // }
	
	eval(value); //dirt simple - just execute the string as javascript in this context.  //ought to catch errors here.
	
}



function onParameter(name,value)
{
	//writeln(">>>>>>>>>>>>>>>>>  onParameter(" + name + ","+ value +") ");
	if(name=="action")
	{
		onAction(value);
	} else {
		//do nothing
		//writeComment("onParameter -- " + name + ", " + value + " -- ");
		return;
	}
}

function onSectionEnd() {
  writeBlock(gPlaneModal.format(17));

  if (((getCurrentSectionId() + 1) >= getNumberOfSections()) ||
      (tool.number != getNextSection().getTool().number)) {
    onCommand(COMMAND_BREAK_CONTROL);
  }

  forceAny();
}

function onClose() {
  writeln("");

  onCommand(COMMAND_COOLANT_OFF);

  if (properties.useG28) {
    writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
    zOutput.reset();
  }

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane

  if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
    if (properties.useG28) {
      writeBlock(gFormat.format(28), gAbsIncModal.format(91), "X" + xyzFormat.format(0), "Y" + xyzFormat.format(0)); // return to home
	}
  } else {
    var homeX;
    if (machineConfiguration.hasHomePositionX()) {
      homeX = "X" + xyzFormat.format(machineConfiguration.getHomePositionX());
    }
    var homeY;
    if (machineConfiguration.hasHomePositionY()) {
      homeY = "Y" + xyzFormat.format(machineConfiguration.getHomePositionY());
    }
	
    //writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), homeX, homeY); 
	writeBlock(gAbsIncModal.format(90)); //2015-10-30 : commented out above line and replaced with this one because homeX and homeY in my particular configuration are arbitrary and I don't want to send the machine to some arbitrary position.
  }

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off
}

function onPassThrough(value)
{
	writeln(value);
}


/*This function reads the specified json file and returns the object contained therein.*/
function getObjectFromJsonFile(pathOfJsonFile)
{
	var myTextFile = new TextFile(pathOfJsonFile,false,"ansi");
	var lineCounter = 0;
	var line;
	var fileContents = "";
	while(!function(){try {line=myTextFile.readln(); eof = false;} catch(error) {eof=true;} return eof;}())  //if the final line is empty (i.e. if the last character in the file is a newline, then that line is not read. So, for instance, an empty file is considered to have 0 lines, according to TextFile.readln. Weird.).
	{
		fileContents += line;
		lineCounter++;
	}
	myTextFile.close();
	//writeln("read " + lineCounter + " lines.");
	
	return JSON.parse(fileContents);

}
