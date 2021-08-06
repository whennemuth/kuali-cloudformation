package org.bu.jenkins.job;

import java.io.PrintWriter;
import java.io.StringWriter;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.mvc.view.AbstractParameterView;

public abstract class AbstractParameterSet {

	Logger logger = LogManager.getLogger(AbstractParameterSet.class.getName());
	
	protected AWSCredentials credentials = AWSCredentials.getInstance();
	protected String ajaxHost;

	public static String stackTraceToHTML(Exception e) {
	    StringWriter sw = new StringWriter();
	    PrintWriter pw = new PrintWriter(sw);
	    if(e.getMessage() != null) {
	      pw.write(e.getMessage());
	    }
	    pw.write("\n");
	    e.printStackTrace(pw);
	    return "<pre>" + sw.toString() + "</pre>";
	}

	public abstract String getRenderedParameter(JobParameterConfiguration configuration);

	public abstract JobParameterMetadata[] getJobParameterMetadata();

	public abstract void checkJobParameterConfig(JobParameterConfiguration config);

	public String getAjaxHost() {
		return ajaxHost;
	}

	public void setAjaxHost(String ajaxHost) {
		this.ajaxHost = ajaxHost;
	}

	public JobParameterMetadata getParameterMetadata(String parmName) {
		for(JobParameterMetadata meta: getJobParameterMetadata()) {
			if(meta.toString().equalsIgnoreCase(parmName)) {
				return meta;
			}
		}
		return null;
	}

	/**
	 * Get a parameterView with the "boilerplate" fields set.
	 * 
	 * @param config
	 * @return
	 */
	protected AbstractParameterView getSparseParameterView(JobParameterConfiguration config, String resolverPrefix) throws Exception {
		EntryMessage m = logger.traceEntry(
				"getSparseParameterView(config.getParameterName()={}, resolverPrefix={})", 
				config==null ? "null" : config.getParameterName(), 
				resolverPrefix);
		JobParameterMetadata parameter = getParameterMetadata(config.getParameterName());
		AbstractParameterView parameterView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return resolverPrefix;
			} 
		}
		.setViewName(parameter.getViewName())
		.setTemplateSelector(parameter.getTemplateSelector());
			
		if(config.getParameterMap().containsKey(parameter.toString())) {
			String value = config.getParameterMap().get(parameter.toString());
			parameterView.setContextVariable("ParameterValue", value);
		}
		if( ! config.isActiveChoices()) {
			parameterView.setContextVariable("ParameterName", parameter.toString());
		}
		
		parameterView.setContextVariable("RenderName", config.isRenderName());
		parameterView.setContextVariable("RenderDescription", config.isRenderDescription());
		
		logger.traceExit(m, parameterView.getViewName());
		return parameterView;
	}

	public AbstractParameterSet() {
		super();
	}

}