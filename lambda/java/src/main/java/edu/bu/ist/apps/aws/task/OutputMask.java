package edu.bu.ist.apps.aws.task;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;

import org.json.JSONException;
import org.json.JSONObject;

import edu.bu.ist.apps.aws.lambda.Logger;

/**
 * All output of a task result gets logged. However if the output contains sensitive information, like passwords, keys, etc.,
 * then you won't want to output those values to logs as is, but in a "masked" form.
 * The choice to mask an output value is determined by its key, which implementing class will have access to. 
 * @author wrh
 *
 */
public interface OutputMask {

	public static final String ALL_FIELDS = "all";
	
	public String getLogOutput(String key, Object value);
	
	public String getOutput(String key, Object value);
	
	/**
	 * Static factory that will return an existing implementation of this interface based on the classname value
	 * from the supplied json object. 
	 * The implementation class must have a constructor with a single string parameter of json.
	 * The json matches the implementation and has no specification here, except that it must parse as json.
	 * 
	 * @param json
	 * @return
	 */
	public static OutputMask getInstance(String json, Logger logger)  {
		
		OutputMask maskImpl = null;
		
		try {
			
			JSONObject jsonObj = new JSONObject(json);
			String className = jsonObj.getString("class");
			Class<?> clazz = Class.forName(className);
			String parameters = jsonObj.getJSONObject("parameters").toString();
			Constructor<?> con = clazz.getConstructor(String.class);
			maskImpl = (OutputMask) con.newInstance(parameters);
			
		} catch (JSONException e) {
			logException(e, logger);
		} catch (ClassNotFoundException e) {
			logException(e, logger);
		} catch (NoSuchMethodException e) {
			logException(e, logger);
		} catch (SecurityException e) {
			logException(e, logger);
		} catch (InstantiationException e) {
			logException(e, logger);
		} catch (IllegalAccessException e) {
			logException(e, logger);
		} catch (IllegalArgumentException e) {
			logException(e, logger);
		} catch (InvocationTargetException e) {
			logException(e, logger);
		}
		
		return maskImpl;
	}
	
	public static void logException(Exception e, Logger logger) {
		logger.log(e.getClass().getSimpleName() + ": " + e.getMessage());
	}
}
