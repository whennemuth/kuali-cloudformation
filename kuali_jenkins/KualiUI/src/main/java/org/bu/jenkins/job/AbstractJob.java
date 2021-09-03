package org.bu.jenkins.job;

import java.lang.reflect.Constructor;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.mvc.controller.kuali.parameter.QueryStringParms;
import org.bu.jenkins.mvc.view.AbstractParameterView;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.SimpleHttpHandler;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

/**
 * A "Job" here is meant an entire jenkins job with all of its fields.
 * This class provides subclasses with the basic functionality for rendering the combined html for all of those
 * fields as a single active choices field. Included with the html is javascript and a hidden state field
 * that assist in driving dynamic behavior and allow the individual fields to act as if they stood apart as 
 * separate active choices fields. A subclass is specific to a certain jenkins job and what subclasses implement 
 * is particular html generation of each field for that job.
 *  
 * @author wrh
 *
 */
public abstract class AbstractJob extends AbstractParameterSet {
	
	Logger logger = LogManager.getLogger(AbstractJob.class.getName());

	public AbstractJob() {
		super();
	}

	public abstract String getJobName();
	
	public abstract boolean isPageRefresh(Map<String, String> parameters);
	
	public abstract void flushCache();
	
	/**
	 * In a jenkins job, the active choices parameters will be rendered individually. However, to get a view of what the 
	 * entire jenkins job will look like, this function will combine all parameter renderings in the job and display them in a
	 * browser as a sort of test harness.
	 * @param parameters
	 * @return
	 */
	public String getRenderedJob(Map<String, String> parameters, boolean developmentMode) {
		EntryMessage m = logger.traceEntry(
				"getRenderedJob(parameters.size()={}, developmentMode={})", 
				parameters==null ? "null" : parameters.size(), 
				developmentMode);
		
		if(isPageRefresh(parameters)) {
			flushCache();
		}
				
 		StringBuilder html = new StringBuilder();
		try {
			html.append(getCssView(logger))
				.append("<form method='GET' name='kuali-parameters' id='kuali-parameters'>")
				.append("<div id='kuali-wrapper'>")
				.append("<fieldset id='all-fields'>")
				.append("<input type='hidden' id='" + getJobName() + "'>");
			// Add the html of each parameter to the output one by one.
			for (JobParameterMetadata fieldMeta : getJobParameterMetadata()) {
				String parmName = fieldMeta.toString();
				JobParameterConfiguration config = JobParameterConfiguration.getNestedFieldInstance(parmName);
				config.setParameterMap(parameters);
				checkJobParameterConfig(config);
				html.append(getRenderedParameter(config));
			}
			html
				.append("</fieldset>")
				.append("</div>")
				.append("</form>");

			if(developmentMode) {
				/**
				 * NOTE: For some unknown reason, including the javascript with all of the parameter html will not work on a
				 * jenkins server (not developmentMode), even with the CORS disabled. The script gets blocked somehow, letting
				 * the html and css through but not showing in the debug window. So, the workaround for this is for a separate
				 * active choices reactive parameter to make it's own http request to acquire the javascript alone (add a 
				 * "?scripts-only=true" querystring parameter to the url). This seems to work.
				 */
				html.append(getJavascriptView(developmentMode));
				html.insert(0, "<html><body>");
				html.append("</body></html>");
			}
			logger.traceExit(m, html.length());
			return html.toString();
		} 
		catch (Exception e) {
			e.printStackTrace(System.out);
			logger.traceExit(m, e.getMessage());
			return stackTraceToHTML(e);
		}
	}

	protected String getJavascriptView(boolean developmentMode) {
		EntryMessage m = logger.traceEntry("getJavascriptView(developmentMode={})", developmentMode);
		AbstractParameterView javascriptView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return "org/bu/jenkins/active_choices/html/job-javascript/";
			} }
			.setViewName("DynamicBehavior")
			.setTemplateSelector("dynamic-behavior")
			.setContextVariable("jobName", getJobName())
			.setContextVariable("mode", developmentMode ? "development" : "UnoChoice")
			.setContextVariable("ajaxHost", ajaxHost);
		String retval = javascriptView.render();
		logger.traceExit(m, retval==null ? "null" : retval.length());
		return retval;
	}

	public static String getCssView(Logger logger) {
		EntryMessage m = logger.traceEntry("getCssView()");
		AbstractParameterView cssView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return "org/bu/jenkins/active_choices/html/job-css/";
			} }
			.setViewName("Stylesheet")
			.setTemplateSelector("stack-stylesheet");
		String retval = cssView.render();
		logger.traceExit(m, retval==null ? "null" : retval.length());
		return retval;
	}

	public static void main(String[] args) throws Exception {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		if(namedArgs.has("job-class")) {
			Class<?> jobclass = Jobs.getClass(namedArgs.get("job-class"));
			Constructor<?> constructor = jobclass.getConstructor(AWSCredentials.class);
			AbstractJob job = (AbstractJob) constructor.newInstance(AWSCredentials.getInstance(namedArgs));
			job.setAjaxHost(namedArgs.get("ajax-host", "127.0.0.1"));			
			
			SimpleHttpHandler handler = new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					try {
						if(parameters.containsKey("scripts-only")) {
							return job.getJavascriptView(namedArgs.getBoolean("developmentMode"));
						}
						else {
							return job.getRenderedJob(parameters, namedArgs.getBoolean("developmentMode"));
						}
					} 
					catch (Exception e) {
						e.printStackTrace(System.out);
						return stackTraceToHTML(e);
					}
				}};
				
			handler
				.setPort(namedArgs.getInt("port"))
				.start();
			
			System.out.println(namedArgs.get("job-class") + " job server started.");
			
			if(namedArgs.getBoolean("browser")) {			
				/**
				 * Get all of the named args except the those that have nothing to do with request parameters.
				 * What remains will be used to construct a query string for visit with browser.
				 */
				Map<String, String> requestParms = namedArgs.getAllNamed(QueryStringParms.asArgArray());
				
				handler.visitWithBrowser(true, requestParms);				
			}
		}
		else {
			System.out.println("Required \"job-class\" argument!");
		}
	}
}