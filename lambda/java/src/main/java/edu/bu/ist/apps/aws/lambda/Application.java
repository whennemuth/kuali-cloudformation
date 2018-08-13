package edu.bu.ist.apps.aws.lambda;

import java.util.Map;

/**
 * Definitions for each application that the CustomResourceHandler could perform a task around and utilities for
 * extracting an application identifier out of a map and validating it can be matched up to one of the enum values.
 * 
 * @author wrh
 *
 */
public enum Application {

	KC("Kuali Research"),
	CORE("cor-main"),
	COI("Conflict of Interest"),
	UNKNOWN("Unknown Application");
	
	private String shortname;

	private Application(String shortname) {
		this.shortname = shortname;
	}
	
	public static Application getApplication(String app) {
		if(app == null)
			return UNKNOWN;
		for(Application a : Application.values()) {
			if(a.name().equalsIgnoreCase(app)) {
				return a;
			}
		}
		return UNKNOWN;
	}
	
	public static Application extractTask(Object obj) {
		return extractApplication(obj, null);
	}
	
	public static Application extractApplication(Object obj, Logger logger) {
		if(obj == null) {
			log(logger, "ERROR! Application could not be found in null object");
			return UNKNOWN;
		}
		if(obj instanceof Map) {
			Map<?,?> map = (Map<?,?>) obj;
			return getApplication(String.valueOf(map.get("application")));
		}
		log(logger, "ERROR! Application could not be found.");
		return UNKNOWN;
	}
	
	private static void log(Logger logger, String message) {
		if(logger == null)
			return;
		logger.log(message);
	}

	public String getShortname() {
		return shortname;
	}
	
}
