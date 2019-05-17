// Enable JavaScript's strict mode. Strict mode catches some common
// programming errors and throws exceptions, prevents some unsafe actions from
// being taken, and disables some confusing and bad JavaScript features.
"use strict";


function make_url(content)
{
  var api = {
    get: function (action, params, async) {
        var api_ver = 3;
        var base_url = ckan.sandbox().client.endpoint;
        params = $.param(params);
        var url = base_url + '/api/' + api_ver + '/action/' + action + '?' + params;
        if (!async) {
            $.ajaxSetup({
                async: false
            });
        }
        return $.getJSON(url);
    }
  };

    var url ="";
    api.get('research_question_show', {
      'id' : content
    }, false)
    .done(function(data) {
      api.get('get_rq_url', {
        name: data.result['name']
      }, false).
      done(function(data) {
        console.log(window.location.host);
        var host = window.location.host;
        url = "http://"+ host + data.result;
        console.log(url);
      });
      });
      return url;
}

ckan.module('visualization_info', function ($) {
  return {
    initialize: function () {
      var resource_id = this.options.resource_id;
      var table_title = this.options.title;
      var rq_ids = this.options.id;
      var rqs ="";
      if(rq_ids == 0)
        rqs = "This dataset contains no research <br/ > questions.";
      else
        rqs = "<strong> Research Questions: </strong>";
      var content =  rqs;
      content += '<br/ >';
      var rqs_list = this.options.rqs;
      if(rqs_list != 0)
      {
      
        rqs_list = rqs_list.replace(/u'/g,"");
        
        rqs_list = rqs_list.replace(/'/g,"").replace("[","").replace("]","");
        var remove_comma = rqs_list.split(',');
        
        rq_ids = rq_ids.replace(/{/g,"");
        rq_ids = rq_ids.replace(/}/g,"");
        rq_ids = rq_ids.replace(/ /g,"");
        rq_ids = rq_ids.split(',');
        for( var i = 0; i < remove_comma.length; ++i)
        {
          var x ="";
          x+= make_url(rq_ids[i]);
          content += '<a href="' + x + '">"' + remove_comma[i]+ '"</a>';
          content += '<br/ >';
        }
      }
      
      this.el.popover({title: "Title: "+table_title,
        content: content,
        html: true,
        placement: 'right'});
    }
    
    };
});