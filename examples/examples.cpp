// MoiSim.cpp : Defines the entry point for the console application.
//

#include <iostream>
#include <string>
#include "example1.h"
#include <unordered_map>
#include <vector>
#include "examples.h"

std::vector<Example> getExamples()
{
	return
	{ example1()};
}

std::string cmdGetOption(int &argc, char **argv, const std::string & option)
{
	char** const end = argv + argc;
	char ** itr = std::find(argv, end, option);
	if (itr != end && ++itr != end)
	{
		return std::string(*itr);
	}
	return std::string();
}

bool cmdOptionExists(int &argc, char **argv, const std::string& option)
{
	char** const end = argv + argc;
	return std::find(argv, end, option) != end;
}

void cmdHelp(std::ostream& stream, int &argc, char **argv)
{
	stream << "Usage: " << argv[0] << " [-options] -e examplename" <<std::endl;
	stream << "where examplename is one of:" << std::endl;
	for (auto example : getExamples())
	{
		stream << '\t' << std::get<0>(example) << '\t' << std::get<1>(example) << std::endl;
	}
	stream << "where options include:" << std::endl;
	stream << "\t-o folder\tSpecifies folder in which results should be saved." << std::endl;
}

int main(int argc, char *argv[])
{
	if (cmdOptionExists(argc, argv, "-h") 
		|| cmdOptionExists(argc, argv, "-help")
		|| cmdOptionExists(argc, argv, "--help")
		|| cmdOptionExists(argc, argv, "-?"))
	{
		cmdHelp(std::cout, argc, argv);
		return 0;
	}
	std::string outputFolder = cmdGetOption(argc, argv, "-o");
	if (outputFolder.empty())
		outputFolder = "simulations";
	std::string exampleName = cmdGetOption(argc, argv, "-e");
	auto examples = getExamples();
	if (exampleName.empty())
	{
		std::cerr << "No example model name specified." << std::endl;
		cmdHelp(std::cerr, argc, argv);
		return 1;
	}
	for (auto example : examples)
	{
		if (std::get<0>(example).compare(exampleName) != 0)
			continue;
		try
		{
			std::get<2>(example)(outputFolder);
			return 0;
		}
		catch (const std::runtime_error& re)
		{
			std::cerr << "Runtime error: " << re.what() << std::endl;
			return 1;
		}
		catch (const std::exception& ex)
		{
			std::cerr << "Error occurred: " << ex.what() << std::endl;
			return 1;
		}
		catch (std::string message)
		{
			std::cerr << "Error occured: " << message << std::endl;
			return 1;
		}
		catch (...)
		{
			std::cerr << "Unknown error occured." << std::endl;
			return 1;
		}
	}
	std::cerr << "Unknown example " << exampleName << ".";
	return 1;
}

