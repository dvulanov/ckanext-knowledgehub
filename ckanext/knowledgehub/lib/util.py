'''Utitlities used accross the extension.
'''


class monkey_patch:
    '''Decorator to monkey patch an object for usage within the function/method
    it decorates.

    It replaces the property in the object it patches with the given
    replacement value. The property is patched only during the execution of the
    decorated function. Before and after the function executes, the property in
    the patched object retains it original value.

    If the object does not have the property before being patched, it will add
    the propery and set it to the patched value.

    An example usage:

        .. code-block: python

            from logging import getLogger
            from unittest import mock

            log = getLogger(__name__)

            @monkey_patch(log, 'debug', mock.Mock()):
            def test_function():
                log.debug('A debug message')

                log.debug.assert_called_once_with('A debug message')


            log.debug('This is visible')
            test_function()
            log.debug('This is also visible')

            # Would print:
            # >> This is visible
            # >> This is also visible

    Another example:

        .. code-block: python

            from os import path

            def funtion_to_test():
                """This is clearly not testable without 'path.isfile' being
                patched.
                """
                if path.isfile('a-file'):
                    print('It is a file')

            # Let's patch 'path.isfile' and write our test
            @monkey_patch(path, 'isfile', mock.Mock())
            def test_function_to_test():
                path.isfile.return_value = True  # set up the mock

                # call the function
                function_to_test()

                # now assert that the mock was called
                path.isfile.assert_called_once_with('a-file')

            # the test should pass

    :param obj: `any`, the object to patch. It may be a simple object, a module
        or a package. This way objects within a module or a package can be
        patched for usage in unit tests.
    :param prop: `str`, the name of the property to patch. The property may or
        may not exist.
    :param patch_with: `any`, the patched value of the property. The property
        will be set to this value during the execution of the decorated
        function or method.

    :returns: `function`, decorated function that retains the name, module and
        doc string as the function it decorates.
    '''
    def __init__(self, obj, prop, patch_with):
        self.obj = obj
        self.prop = prop
        self.patch_with = patch_with

    def __call__(self, method):
        original_prop = None
        if hasattr(self.obj, self.prop):
            original_prop = getattr(self.obj, self.prop)

        def _with_patched(*args, **kwargs):
            # patch
            setattr(self.obj, self.prop, self.patch_with)
            try:
                return method(*args, **kwargs)
            finally:
                # unpatch
                if original_prop is not None:
                    setattr(self.obj, self.prop, original_prop)
                else:
                    delattr(self.obj, self.prop)
        _with_patched.__name__ = method.__name__
        _with_patched.__module__ = method.__module__
        _with_patched.__doc__ = method.__doc__
        return _with_patched