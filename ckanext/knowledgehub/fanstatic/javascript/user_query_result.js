(function (_, jQuery) {
    'use strict';

    const SKIP_PAGES = ['organization', 'group']
    const DATASET_TYPE = 'dataset'
    const RQ_TYPE = 'research_question'
    const DASHBOARD_TYPE = 'dashboard'

    var api = {
        get: function (action, params) {
            var api_ver = 3;
            var base_url = ckan.sandbox().client.endpoint;
            params = $.param(params);
            var url = base_url + '/api/' + api_ver + '/action/' + action + '?' + params;
            return $.getJSON(url);
        },
        post: function (action, data) {
            var api_ver = 3;
            var base_url = ckan.sandbox().client.endpoint;
            var url = base_url + '/api/' + api_ver + '/action/' + action;
            return $.post(url, data, 'json');
        }
    };

    function saveUserQueryResult(query_text, result_type, result_id, user_id) {
        api.post('user_query_result_save', {
            query_text: query_text,
            query_type: result_type,
            result_id: result_id,
        });
    }

    $(document).ready(function () {
        var save_user_query = function(callback) {
            var tab_content = $('.tab_content');

            tab_content.on('click', '.dataset-heading', function(e) {
                e.preventDefault();
                e.stopPropagation();
                var dataset_content = $(this).parent('.dataset-content');
                var result_id = dataset_content.find('#dataset-id').val();
                callback(DATASET_TYPE, result_id);
                setTimeout(function(){
                    window.location = $('a', this).attr('href');
                }.bind(this), 0);
                return false;
            });

            tab_content.on('click', '.rq-heading', function (e) {
                e.preventDefault()
                e.stopPropagation()
                var rq_content = $(this).parent('.rq-box');
                var result_id = rq_content.find('#rq-id').val();
                callback(RQ_TYPE, result_id);
                setTimeout(function(){  
                    window.location = $('a', this).attr('href');
                }.bind(this), 10);
                return false;
            });

            tab_content.on('click', '.dashboard-link', function (e) {
                e.preventDefault()
                e.stopPropagation()
                // var dashboard_content = $(this).parent('#tabs-dashboards');
                // var result_id = dashboard_content.find('#dashboard-id').val();
                var result_id = $(this).attr('id');
                callback(DASHBOARD_TYPE, result_id);
                setTimeout(function(){
                    window.location = $(this).attr('href');
                }.bind(this), 0);
                return false;
            });
        }

        save_user_query(function(result_type, result_id){
            var url = window.location.href
            var parts = url.split('/')
            var page = parts[3]
            if (!SKIP_PAGES.includes(page)) {
                var query_text = $('#field-giant-search').val();
                if (query_text) {
                    var user_id = $('#user-id').val();
                    saveUserQueryResult(query_text, result_type, result_id, user_id)
                }
            }
        });
    });
})(ckan.i18n.ngettext, $);