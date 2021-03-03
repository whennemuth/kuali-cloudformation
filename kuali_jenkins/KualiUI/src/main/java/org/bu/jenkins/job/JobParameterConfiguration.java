package org.bu.jenkins.job;

import java.util.HashMap;
import java.util.Map;

/**
 * Convenience bean to consolidate parameters consumed by getRenderedParameter
 * @author wrh
 *
 */
public class JobParameterConfiguration {
	private String parameterName;
	private Map<String, String> parameterMap = new HashMap<String, String>();
	private boolean fragment;
	private boolean activeChoices;
	private boolean developmentMode;
	private JobParameterConfiguration() { super(); }
	public String getParameterName() {
		if(parameterName == null) return null;
		return parameterName;
	}
	public void setParameterName(String parameterName) {
		this.parameterName = parameterName;
	}
	public Map<String, String> getParameterMap() {
		return parameterMap;
	}
	public JobParameterConfiguration setParameterMap(Map<String, String> parameterMap) {
		if(parameterMap != null) {
			this.parameterMap.putAll(parameterMap);
		}
		return this;
	}
	public boolean isFragment() {
		return fragment;
	}
	public void setFragment(boolean fragment) {
		this.fragment = fragment;
	}
	public boolean isActiveChoices() {
		return activeChoices;
	}
	public void setActiveChoices(boolean activeChoices) {
		this.activeChoices = activeChoices;
	}
	public boolean isStandalone() {
		return this.isFragment() && ! this.isActiveChoices();
	}
	public static JobParameterConfiguration getInstance() {
		return new JobParameterConfiguration();
	}
	public boolean isDevelopmentMode() {
		return developmentMode;
	}
	public void setDevelopmentMode(boolean developmentMode) {
		this.developmentMode = developmentMode;
	}
	public static JobParameterConfiguration forEntireJobInstance(String parameterName) {
		JobParameterConfiguration config = new JobParameterConfiguration();
		config.parameterName = parameterName;
		return config;
	}
	public static JobParameterConfiguration forEntireJobInstance(String parameterName, Map<String, String> parameterMap) {
		JobParameterConfiguration config = new JobParameterConfiguration();
		config.parameterName = parameterName;
		config.parameterMap = parameterMap;
		return config;
	}
	public static JobParameterConfiguration forActiveChoicesFragmentInstance(String parameterName) {
		JobParameterConfiguration config = new JobParameterConfiguration();
		config.parameterName = parameterName;
		config.activeChoices = true;
		config.fragment = true;
		return config;
	}
	public static JobParameterConfiguration forActiveChoicesFragmentInstance(String parameterName, Map<String, String> parameterMap) {
		JobParameterConfiguration config = new JobParameterConfiguration();
		config.parameterName = parameterName;
		config.activeChoices = true;
		config.fragment = true;
		config.parameterMap = parameterMap;
		return config;
	}
	public static JobParameterConfiguration forTestFragmentInstance(String parameterName) {
		JobParameterConfiguration config = forEntireJobInstance(parameterName);
		config.fragment = true;
		return config;			
	}
}