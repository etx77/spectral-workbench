describe("API", function() {

  var graph, ajaxSpy;

  beforeEach(function() {

    fixture = loadFixtures('graph.html');

    jasmine.Ajax.install();

    ajaxSpy = spyOn($, "ajax").and.callFake(function(object) {

      var response;

      if      (object.url == '/spectrums/9.json') response = object.success(TestResponses.spectrum.success.responseText);
      else if (object.url == '/spectrums/9/tags') response = object.success(TestResponses.tags.success.responseText);
      else if (object.url == '/spectrums/clone_calibration/9.json') response = object.success('success');
      else if (object.url == '/match/search/9.json') response = object.success([TestResponses.spectrum.success.responseText]); // return an array containing same spectrum
      else response = 'none';

      // check this if you have trouble faking a server response: 
      if (response != 'none') console.log('Faked response to:', object.url)
      else console.log('Failed to fake response to:', object.url)

    });

  });


  afterEach(function() {

    jasmine.Ajax.uninstall();

  });


  it("should be labelled version 2.0", function() {
    expect(new SpectralWorkbench.API().version).toBe('2.0');
  });


  it("can create notifications in the DOM", function() {

    var noticeEl = SpectralWorkbench.API.Core.notify('Hello, world!', 'success');

    expect(noticeEl.html()).toBe('<b>Success:</b> Hello, world!');
    expect(noticeEl.html()).not.toBe('Goodbye, world!');
    expect(noticeEl.hasClass('alert-success')).toBe(true);

    var noticeEl = SpectralWorkbench.API.Core.notify('Hello, world!', 'error');

    expect($('.notifications-container p').length).toBe(2);
    expect(noticeEl.hasClass('alert-error')).toBe(true);

  });


  // expensive to test this; also, let's put it in Spectrum?:
  it("can export SVG", function(done) {

    graph = new SpectralWorkbench.Graph({
      spectrum_id: 9,
      calibrated: true,
      onImageComplete: function() { done(); } // fires when graph.image is loaded, so that later tests can run
    });

    expect(graph).toBeDefined();
    expect(graph.datum).toBeDefined();

    var svgEl = SpectralWorkbench.API.Core.exportSVG('export');

    expect(svgEl).toBeDefined();
    expect(svgEl.attr('download')).toBeDefined();
    expect(svgEl.attr('href')).toBeDefined();

  });


  var copyCalibrationCallbackSpy;

  it("can copy calibrations with copyCalibration()", function(done) {

    copyCalibrationCallbackSpy = jasmine.createSpy('success');

    SpectralWorkbench.API.Core.copyCalibration(9, graph.datum, function(response) {

      expect(response).toBe('success');

      copyCalibrationCallbackSpy();

      done();

    });

    // graph should refresh with datum.fetch();

    // check extents
    expect(graph.datum.getFullExtentX()).toEqual([ 269.089, 958.521 ]);

  });


  it("generates copyCalibration callback", function() {

    expect(copyCalibrationCallbackSpy).toHaveBeenCalled();

  });


  it("can transform graph data", function() {

    expect(graph.datum.average[100]).toEqual({ y: 0.21, x: 355.376 });

    // uses function(R,G,B,A,X,Y,I,P,a,r,g,b)
    SpectralWorkbench.API.Core.transform(graph.datum, 'R+G*X'); // random transform

    expect(graph.datum.average[100]).toEqual({ y: 53.526399999999995, x: 355.376 });

  });


  it("can limit graphed data to wavelength range", function() {

    expect(graph.datum.getFullExtentX()).toEqual([ 269.089, 958.521 ]);
    expect(graph.datum.getExtentX()).toEqual([ 269.089, 958.521 ]);

    SpectralWorkbench.API.Core.range(graph.datum, 500, 600);

    expect(graph.datum.getFullExtentX()).toEqual([ 269.089, 958.521 ]);
    expect(graph.datum.getExtentX()).not.toEqual([ 269.089, 958.521 ]);


  });


  var blendCallbackSpy;

  it("can blend graphed spectrum data with that of another spectrum", function(done) {

    blendCallbackSpy = jasmine.createSpy('success');

    expect(graph.datum.average[100].y).toEqual(405.64124999999996);

    // uses function(R1,G1,B1,A1,R2,G2,B2,A2,X,Y,P)
    SpectralWorkbench.API.Core.blend(graph.datum, 9, 'R1+G2*X', function() { // random transform

      blendCallbackSpy();

      expect(graph.datum.average[100].y).not.toEqual(405.64124999999996);
      expect(graph.datum.average[100].y).toEqual(0.87);

      done();

    });

  });


  it("generates blendCalibration callback", function() {

    expect(blendCallbackSpy).toHaveBeenCalled();

  });


  var subtractCallbackSpy;

  it("can subtract indicated spectrum data from own data", function(done) {

    subtractCallbackSpy = jasmine.createSpy('success');

    expect(graph.datum.average[100].y).toEqual(0.87);

    // uses function(R1,G1,B1,A1,R2,G2,B2,A2,X,Y,P)
    SpectralWorkbench.API.Core.subtract(graph.datum, 9, function() { // random transform

      subtractCallbackSpy();

      expect(graph.datum.average[100].y).toEqual(0.18999999999999995); // not quite zero, but close
      expect(graph.datum.average[100].y).not.toEqual(400);

      done();

    });

  });


  it("generates subtract callback", function() {

    expect(subtractCallbackSpy).toHaveBeenCalled();

  });


  it("can smooth graph data", function() {

    expect(graph.datum.average[100].y).toEqual(0.18999999999999995);

    SpectralWorkbench.API.Core.smooth(graph.datum, 20); // random transform

    expect(graph.datum.average[100].y).toEqual(0.12281591779711726);

  });


  // fetch is already tested, in copyCalibration()
  // fetch: function(graph, id, callback) {


  it("can compare graph data from another spectrum", function() {

    SpectralWorkbench.API.Core.compare(graph, graph.datum.json); // just compare it to itself

    expect(graph.comparisons).toBeDefined();
    expect(graph.comparisons.length).toEqual(1);

    expect(graph.data.datum().length).toBe(5);

  });


  var similarCallbackSpy;

  it("can request list of similar spectra from server-side app", function(done) {

    similarCallbackSpy = jasmine.createSpy('success');

    // if we provide no callback, it'll run API.Core.compare
    SpectralWorkbench.API.Core.similar(graph, 9, 20, function(graph, spectrum) {

      similarCallbackSpy();

      expect(spectrum).toBeDefined();
      expect(spectrum.id).toBe(9);

      done();

    });

  });


  it("generates similar() callback", function() {

    expect(similarCallbackSpy).toHaveBeenCalled();

  });


  it("can find max peak in different channels with findMax()", function() {

    var max = SpectralWorkbench.API.Core.findMax(graph.datum.json.data.lines, 'red');
    expect(max.value).toBe(0);
    expect(max.index).toBe(0);

    var max2 = SpectralWorkbench.API.Core.findMax(graph.datum.json.data.lines, 'red', max.index + 1);
    expect(max2.value).toBe(0);
    expect(max2.index).toBe(0);

  });


  it("can attempt a calibration and return guessed peak positions with attemptCalibration()", function() {
    
    var peaks = SpectralWorkbench.API.Core.attemptCalibration(graph);
    expect(peaks.length).toBe(3);

  });


  it("can assess a calibration by comparing peak positions with calibrationFit()", function() {
    
    var error = SpectralWorkbench.API.Core.calibrationFit(100, 70, 10);
    expect(error).toBe(17.16461628588166);

  });


  it("can assess a calibration by using b and g peak positions to estimate an r position with calibrationFitGB()", function() {
    
    var error = SpectralWorkbench.API.Core.calibrationFitGB(545, 436, graph.datum);
    expect(error).toBe(0);

    // that isn't quite right. But it's possible there's no data given the wavelengths I provided.

  });


  it("can assess a calibration with RMSE using rmseCalibration()", function() {

    // very crappy, i.e. just guessed:     
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 300, 500))).toBe(19);

    // derived from use of the interface itself: 
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 193.24, 322.4))).toBe(12);
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 193.24, 321.4))).toBe(7);
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 193.24, 358.45))).toBe(25);
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 183.23, 358.45))).toBe(27);
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 193.24, 440.55))).toBe(30);
    expect(parseInt(SpectralWorkbench.API.Core.rmseCalibration(graph.datum, 435.83, 546.07, 102.13, 504.63))).toBe(146);

  });


  // don't test these yet:
  //alertOverexposure: function(datum) {
  //alertTooDark: function(datum) {


});
