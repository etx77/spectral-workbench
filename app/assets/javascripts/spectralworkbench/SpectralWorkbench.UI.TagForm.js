SpectralWorkbench.UI.TagForm = Class.extend({

  init: function(_graph, callback) {

    var tagForm = this;

    tagForm.selector = "#tag-form-" + _graph.datum.id;
    tagForm.el = $(tagForm.selector);
    tagForm.input = tagForm.el.find('input.name');

    tagForm.el.bind('submit', function(e){

      e.preventDefault();

      tagForm.input.val().split(',').forEach(function(tagname) {

        _graph.datum.addTag(tagname, function() {

          tagForm.input.val('');
          if (callback) callback();

        });

      });

    });

    tagForm.el.bind('ajax:beforeSend', function(){

      tagForm.input.prop('disabled',true)
      $('#tags .loading').remove();

    });

    tagForm.error = function(msg) {

      $('#taginput').prop('disabled',false);
      
      tagForm.el.find('input.name').val("");
      tagForm.el.find('.control-group').removeClass('error');
      tagForm.el.find('.control-group .help-inline').remove();
      
      tagForm.el.find('.control-group').addClass('error');
      tagForm.el.find('.control-group .help-inline').remove();
      tagForm.el.find('.control-group').append('<span class="help-inline">'+msg+'</span>');
      
      tagForm.el.find('input.name').prop('disabled',false);

    }

    return tagForm;

  }

});

///////////////////LEGACY////////////////

SpectralWorkbench.UI.initTagForm = function(selector, spectrum_id) {

  $(selector).bind('submit', function(e){

    e.preventDefault();

    var tagname = $(selector + ' input.name').val();

    // callback handles only those 
    SpectralWorkbench.UI.LegacyAddTag(spectrum_id, tagname, function(response) {

      $(selector + ' input.name').val("");
      $(selector + ' .control-group').removeClass('error');
      $(selector + ' .control-group .help-inline').remove();

      if (response['errors'].length > 0) {

        $(selector + ' .control-group').addClass('error');
        $(selector + ' .control-group .help-inline').remove();
        $(selector + ' .control-group').append('<span class="help-inline">'+response['errors']+'</span>');

      }

      $(selector + ' input.name').prop('disabled',false);

    });

  });

  $(selector).bind('ajax:beforeSend', function(){

    $(selector + ' input.name').prop('disabled',true)

  });

}



SpectralWorkbench.UI.LegacyAddTag = function(spectrum_id, name, callback) {

  $.ajax({
    url: "/tags",
    type: "POST",

    data: {
      authenticity_token: $('meta[name=csrf-token]').attr('content'),
      tag: {
        spectrum_id: spectrum_id,
        name: name
      }
    },

    success: function(response) {

      response = JSON.parse(response);

      $.each(response['saved'],function(i,tag) {

        var tag_name = tag[0],
            tag_id   = tag[1],
            color    = "";

        // we use CSS classnames to identify tag types
        if (tag_name.match(/[a-zA-Z-]+:[a-zA-Z0-9-]+/)) color = " purple";

        $('#tags').append(" <span id='tag_"+tag_id+"' rel='tooltip' title='This is a powertag.' class='label label-info" + color + "'><a href='/tags/"+tag_name+"'>"+tag_name+"</a> <a class='tagdelete' data-method='delete' href='/tags/"+tag_id+"'>x</a></span> ");

        // deletion listener
        $('#tag_'+tag_id).bind('ajax:success', function(e,tagid){
          $('#tag_'+tagid).remove();
        });

      });

      $('#taginput').prop('disabled',false);

      callback(response);

    },

  });

}
